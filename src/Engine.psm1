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

function Get-DebloatActionCommand {
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Action
    )

    switch ($Action.Kind) {
        'Registry' {
            return @($Action.Registry | ForEach-Object { Get-DebloatRegistryCommand -Operation $_ }) -join '; '
        }
        'Packages' {
            $commands = foreach ($pattern in @($Action.PackagePatterns)) {
                Get-DebloatPackageRemovalCommand -Pattern $pattern
            }
            return @($commands) -join '; '
        }
        'Special' {
            $commands = @{
                SetCustomPowerPlan = 'powercfg.exe /duplicatescheme SCHEME_MIN; powercfg.exe /setactive <PulpoCustomGuid>'
                CleanTemporaryFiles = "Remove-Item -LiteralPath '`$env:SystemRoot\Prefetch\*','`$env:SystemRoot\Temp\*','`$env:TEMP\*' -Recurse -Force"
                DisableHibernation = 'powercfg.exe /hibernate off'
                DisableReservedStorage = 'Set-WindowsReservedStorageState -State Disabled'
                RemoveOneDrive = 'OneDriveSetup.exe /uninstall'
                DisableRecall = "Disable-WindowsOptionalFeature -FeatureName 'Recall' -Online -NoRestart"
                DisableTelemetryTasks = 'Disable-ScheduledTask -InputObject <tarea de telemetria>'
                EnableClassicContextMenu = 'reg.exe add "HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" /ve /t REG_SZ /d "" /f'
            }
            return [string]$commands[[string]$Action.Handler]
        }
        default {
            return "Tipo de accion no admitido: $($Action.Kind)"
        }
    }
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
        & $ProgressCallback 'Creando punto de restauracion obligatorio (limite: 120 segundos)' 0 ($actions.Count + $services.Count) $context.SessionPath
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
                $command = "ProgressCallback '$($action.Title)' $current $total '$($context.SessionPath)'"
                Write-DebloatNotApplied -Context $context -Level Warning -Component 'Progress' -Instruction "Actualizar el progreso para $($action.Title)" -Command $command -Reason $_.Exception.Message -Data @{ ActionId = $action.Id }
            }
            try {
                $actionWarnings = switch ($action.Kind) {
                    'Registry' { Invoke-DebloatRegistryAction -Context $context -Action $action }
                    'Packages' { Invoke-DebloatPackageAction -Context $context -Action $action }
                    'Special' { Invoke-DebloatSpecialAction -Context $context -Action $action }
                    default { throw [System.InvalidOperationException]::new("Tipo de accion no admitido: $($action.Kind)") }
                }
                $warningCount += [int]$actionWarnings
            }
            catch {
                $warningCount++
                $command = Get-DebloatActionCommand -Action $action
                Write-DebloatNotApplied -Context $context -Level Warning -Component 'Engine' -Instruction $action.Title -Command $command -Reason $_.Exception.Message -Data @{ ActionId = $action.Id; Title = $action.Title }
            }
        }

        foreach ($service in $services) {
            $current++
            try {
                & $ProgressCallback $service.Title $current $total $context.SessionPath
            }
            catch {
                $warningCount++
                $command = "ProgressCallback '$($service.Title)' $current $total '$($context.SessionPath)'"
                Write-DebloatNotApplied -Context $context -Level Warning -Component 'Progress' -Instruction "Actualizar el progreso para $($service.Title)" -Command $command -Reason $_.Exception.Message -Data @{ ServiceId = $service.Id }
            }
            try {
                $warningCount += Invoke-DebloatServiceAction -Context $context -ServiceEntry $service
            }
            catch {
                $warningCount++
                $command = Get-DebloatServiceCommand -Name $service.Pattern -StartupType $service.StartupType
                Write-DebloatNotApplied -Context $context -Level Warning -Component 'Engine' -Instruction $service.Title -Command $command -Reason $_.Exception.Message -Data @{ ServiceId = $service.Id; Title = $service.Title }
            }
        }

        $completionStatus = if ($warningCount -gt 0) { 'CompletedWithWarnings' } else { 'Completed' }
        $warningMessage = if ($warningCount -gt 0) { "La optimizacion finalizo con $warningCount advertencias. Revisa el registro." } else { '' }
        Complete-DebloatSession -Context $context -Status $completionStatus -ErrorMessage $warningMessage
        $level = if ($warningCount -gt 0) { 'Warning' } else { 'Success' }
        Write-DebloatLog -Context $context -Level $level -Component 'Engine' -Message 'Optimizacion completada.' -Data @{ Actions = $actions.Count; Services = $services.Count; Warnings = $warningCount }
        $debugReportPath = Save-DebloatDebugReport -SessionPath $context.SessionPath
        return [pscustomobject]@{
            SessionPath = $context.SessionPath
            WarningCount = $warningCount
            DebugReportPath = $debugReportPath
        }
    }
    catch {
        $failure = $_
        $_.Exception.Data['SessionPath'] = $context.SessionPath
        $actionIdsLiteral = ConvertTo-DebloatPowerShellLiteral -Value ([string[]]$ActionIds)
        $serviceIdsLiteral = ConvertTo-DebloatPowerShellLiteral -Value ([string[]]$ServiceIds)
        $command = "Invoke-DebloatSelection -ActionIds $actionIdsLiteral -ServiceIds $serviceIdsLiteral"
        Write-DebloatNotApplied -Context $context -Level Error -Component 'Engine' -Instruction 'Completar la seleccion de optimizacion' -Command $command -Reason $_.Exception.Message -Data @{ ErrorType = $_.Exception.GetType().FullName }
        Complete-DebloatSession -Context $context -Status Failed -ErrorMessage $_.Exception.Message
        $debugReportPath = Save-DebloatDebugReport -SessionPath $context.SessionPath
        $failure.Exception.Data['DebugReportPath'] = $debugReportPath
        throw $failure
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
        Save-DebloatDebugReport -SessionPath $context.SessionPath | Out-Null
        return $sessionPath
    }
    catch {
        $failure = $_
        Write-DebloatNotApplied -Context $context -Level Error -Component 'Engine' -Instruction 'Restaurar la ultima sesion interna' -Command 'Restore-LatestDebloatSession' -Reason $_.Exception.Message -Data @{ ErrorType = $_.Exception.GetType().FullName }
        $debugReportPath = Save-DebloatDebugReport -SessionPath $context.SessionPath
        $failure.Exception.Data['SessionPath'] = $context.SessionPath
        $failure.Exception.Data['DebugReportPath'] = $debugReportPath
        throw $failure
    }
}

Export-ModuleMember -Function Invoke-DebloatSelection, Restore-LatestDebloatSession
