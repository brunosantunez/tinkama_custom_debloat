Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Common.psm1')
Import-Module (Join-Path $PSScriptRoot 'Backup.psm1')
Import-Module (Join-Path $PSScriptRoot 'Registry.psm1')
Import-Module (Join-Path $PSScriptRoot 'Services.psm1')
Import-Module (Join-Path $PSScriptRoot 'Packages.psm1')
Import-Module (Join-Path $PSScriptRoot 'SystemTweaks.psm1')

function Get-SelectedCatalogEntries {
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [object[]]$Entries,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Ids,

        [Parameter(Mandatory)]
        [string]$EntryType
    )

    $selected = [System.Collections.Generic.List[object]]::new()
    foreach ($id in $Ids) {
        $matches = @($Entries | Where-Object Id -eq $id)
        if ($matches.Count -ne 1) {
            throw [System.IO.InvalidDataException]::new("$EntryType inexistente o duplicado: $id")
        }
        $selected.Add($matches[0])
    }
    return [object[]]$selected
}

function Invoke-DebloatSelection {
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [Parameter(Mandatory)]
        [pscustomobject]$Catalog,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$ActionIds,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$ServiceIds,

        [Parameter(Mandatory)]
        [scriptblock]$ProgressCallback
    )

    Assert-DebloatSupportedSystem
    if ($ActionIds.Count + $ServiceIds.Count -eq 0) {
        throw [System.ArgumentException]::new('La seleccion no contiene acciones ni servicios.')
    }
    $actions = @(Get-SelectedCatalogEntries -Entries @($Catalog.Actions) -Ids $ActionIds -EntryType 'Accion')
    $services = @(Get-SelectedCatalogEntries -Entries @($Catalog.Services) -Ids $ServiceIds -EntryType 'Servicio')
    $context = New-DebloatSession -ProjectRoot $ProjectRoot -ActionIds $ActionIds -ServiceIds $ServiceIds

    try {
        & $ProgressCallback 'Creando punto de restauracion obligatorio' 0 ($actions.Count + $services.Count) $context.SessionPath
        New-DebloatRestorePoint -Context $context -Description 'Revertir cambios - Pulpo Custom Debloat'
        Export-DebloatAppxInventory -Context $context

        $warningCount = 0
        $current = 0
        $total = $actions.Count + $services.Count
        foreach ($action in $actions) {
            $current++
            try {
                & $ProgressCallback $action.Title $current $total $context.SessionPath
            }
            catch {
                $warningCount++
                Write-DebloatLog -Context $context -Level Warning -Component 'Progress' -Message 'No se pudo actualizar el progreso; la optimizacion continuara.' -Data @{ ActionId = $action.Id; Error = $_.Exception.Message }
            }
            try {
                $actionWarnings = switch ($action.Kind) {
                    'Registry' { Invoke-DebloatRegistryAction -Context $context -Action $action }
                    'Packages' { Invoke-DebloatPackageAction -Context $context -Action $action }
                    'Special' {
                        Invoke-DebloatSpecialAction -Context $context -Action $action | Out-Null
                        0
                    }
                    default { throw [System.InvalidOperationException]::new("Tipo de accion no admitido: $($action.Kind)") }
                }
                $warningCount += [int]$actionWarnings
            }
            catch {
                $warningCount++
                Write-DebloatLog -Context $context -Level Warning -Component 'Engine' -Message 'Se omitio una accion y la optimizacion continuara.' -Data @{ ActionId = $action.Id; Title = $action.Title; Error = $_.Exception.Message }
            }
        }

        foreach ($service in $services) {
            $current++
            try {
                & $ProgressCallback $service.Title $current $total $context.SessionPath
            }
            catch {
                $warningCount++
                Write-DebloatLog -Context $context -Level Warning -Component 'Progress' -Message 'No se pudo actualizar el progreso; la optimizacion continuara.' -Data @{ ServiceId = $service.Id; Error = $_.Exception.Message }
            }
            try {
                $warningCount += Invoke-DebloatServiceAction -Context $context -ServiceEntry $service
            }
            catch {
                $warningCount++
                Write-DebloatLog -Context $context -Level Warning -Component 'Engine' -Message 'Se omitio una accion de servicio y la optimizacion continuara.' -Data @{ ServiceId = $service.Id; Title = $service.Title; Error = $_.Exception.Message }
            }
        }

        $completionStatus = if ($warningCount -gt 0) { 'CompletedWithWarnings' } else { 'Completed' }
        $warningMessage = if ($warningCount -gt 0) { "La optimizacion finalizo con $warningCount advertencias. Revisa el registro." } else { '' }
        Complete-DebloatSession -Context $context -Status $completionStatus -ErrorMessage $warningMessage
        $level = if ($warningCount -gt 0) { 'Warning' } else { 'Success' }
        Write-DebloatLog -Context $context -Level $level -Component 'Engine' -Message 'Optimizacion completada.' -Data @{ Actions = $actions.Count; Services = $services.Count; Warnings = $warningCount }
        return [pscustomobject]@{
            SessionPath = $context.SessionPath
            WarningCount = $warningCount
        }
    }
    catch {
        $_.Exception.Data['SessionPath'] = $context.SessionPath
        Write-DebloatLog -Context $context -Level Error -Component 'Engine' -Message 'La optimizacion se detuvo por un error.' -Data @{ Error = $_.Exception.Message; ErrorType = $_.Exception.GetType().FullName }
        Complete-DebloatSession -Context $context -Status Failed -ErrorMessage $_.Exception.Message
        throw
    }
}

function Restore-LatestDebloatSession {
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    Assert-DebloatSupportedSystem
    $sessionPath = Get-LatestDebloatSessionPath
    $context = New-DebloatContext -SessionPath $sessionPath
    New-DebloatRestorePoint -Context $context -Description 'Antes de revertir - Pulpo Custom Debloat'

    try {
        Restore-DebloatServices -Context $context
        Restore-DebloatSpecialState -Context $context
        Restore-DebloatRegistry -Context $context
        Complete-DebloatSession -Context $context -Status Restored -ErrorMessage ''
        Write-DebloatLog -Context $context -Level Success -Component 'Engine' -Message 'Restauracion interna completada.' -Data @{ ProjectRoot = $ProjectRoot }
        return $sessionPath
    }
    catch {
        Write-DebloatLog -Context $context -Level Error -Component 'Engine' -Message 'La restauracion se detuvo por un error.' -Data @{ Error = $_.Exception.Message; ErrorType = $_.Exception.GetType().FullName }
        throw
    }
}

Export-ModuleMember -Function Invoke-DebloatSelection, Restore-LatestDebloatSession
