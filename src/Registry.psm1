Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Common.psm1')

function Get-RegistryValueState {
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Exists = $false; Type = $null; Value = $null }
    }

    $key = Get-Item -LiteralPath $Path
    $valueName = if ($Name -eq '@Default') { '' } else { $Name }
    if ($valueName -notin $key.GetValueNames()) {
        return [pscustomobject]@{ Exists = $false; Type = $null; Value = $null }
    }

    $value = $key.GetValue($valueName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    return [pscustomobject]@{
        Exists = $true
        Type = $key.GetValueKind($valueName).ToString()
        Value = $value
    }
}

function ConvertTo-RegistryValue {
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [object]$Value,

        [Parameter(Mandatory)]
        [ValidateSet('DWord', 'QWord', 'String', 'ExpandString', 'MultiString', 'Binary')]
        [string]$Type
    )

    switch ($Type) {
        'DWord' { return [int]$Value }
        'QWord' { return [long]$Value }
        'Binary' { return [byte[]]@($Value) }
        'MultiString' { return [string[]]@($Value) }
        'String' { return [string]$Value }
        'ExpandString' { return [string]$Value }
    }
}

function Open-DebloatWritableRegistryKey {
    [OutputType([Microsoft.Win32.RegistryKey])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $pathMatch = [regex]::Match($Path, '^(HKLM|HKCU):\\(.+)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $pathMatch.Success) {
        throw [System.ArgumentException]::new("Ruta de Registro no admitida: $Path")
    }

    $hive = if ($pathMatch.Groups[1].Value.ToUpperInvariant() -eq 'HKLM') {
        [Microsoft.Win32.RegistryHive]::LocalMachine
    }
    else {
        [Microsoft.Win32.RegistryHive]::CurrentUser
    }

    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, [Microsoft.Win32.RegistryView]::Default)
    try {
        $key = $baseKey.OpenSubKey($pathMatch.Groups[2].Value, $true)
    }
    catch [System.UnauthorizedAccessException] {
        throw [System.UnauthorizedAccessException]::new("No se puede abrir la clave para escritura: $Path. Revisa sus permisos o directivas.", $_.Exception)
    }
    finally {
        $baseKey.Dispose()
    }

    if ($null -eq $key) {
        throw [System.IO.DirectoryNotFoundException]::new("No se encontro la clave de Registro despues de crearla: $Path")
    }
    return $key
}

function Save-RegistryValueSnapshot {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context,

        [Parameter(Mandatory)]
        [string]$ActionId,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $snapshotPath = Join-Path $Context.SessionPath 'registry.json'
    $records = @()
    if (Test-Path -LiteralPath $snapshotPath -PathType Leaf) {
        $records = @(Read-DebloatJson -Path $snapshotPath)
    }
    if (@($records | Where-Object { $_.Path -eq $Path -and $_.Name -eq $Name }).Count -gt 0) {
        return
    }

    $state = Get-RegistryValueState -Path $Path -Name $Name
    $records += [pscustomobject]@{
        ActionId = $ActionId
        Path = $Path
        Name = $Name
        Exists = $state.Exists
        Type = $state.Type
        Value = $state.Value
    }
    Save-DebloatJson -InputObject ([object[]]$records) -Path $snapshotPath
}

function Set-DebloatRegistryValue {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context,

        [Parameter(Mandatory)]
        [string]$ActionId,

        [Parameter(Mandatory)]
        [pscustomobject]$Operation
    )

    Save-RegistryValueSnapshot -Context $Context -ActionId $ActionId -Path $Operation.Path -Name $Operation.Name
    if (-not (Test-Path -LiteralPath $Operation.Path)) {
        New-Item -Path $Operation.Path -Force | Out-Null
    }

    $valueName = if ($Operation.Name -eq '@Default') { '' } else { [string]$Operation.Name }
    $value = ConvertTo-RegistryValue -Value $Operation.Value -Type $Operation.Type
    $kind = [Microsoft.Win32.RegistryValueKind]::$($Operation.Type)
    $key = Open-DebloatWritableRegistryKey -Path $Operation.Path
    try {
        $key.SetValue($valueName, $value, $kind)
    }
    finally {
        $key.Dispose()
    }
    Write-DebloatLog -Context $Context -Level Info -Component 'Registry' -Message 'Valor de Registro aplicado.' -Data @{ ActionId = $ActionId; Path = $Operation.Path; Name = $Operation.Name; Type = $Operation.Type; Value = $Operation.Value }
}

function Invoke-DebloatRegistryAction {
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context,

        [Parameter(Mandatory)]
        [pscustomobject]$Action
    )

    $failureCount = 0
    foreach ($operation in @($Action.Registry)) {
        try {
            Set-DebloatRegistryValue -Context $Context -ActionId $Action.Id -Operation $operation
        }
        catch {
            $failureCount++
            Write-DebloatLog -Context $Context -Level Warning -Component 'Registry' -Message 'Se omitio un valor de Registro y la optimizacion continuara.' -Data @{ ActionId = $Action.Id; Path = $operation.Path; Name = $operation.Name; Error = $_.Exception.Message }
        }
    }
    $level = if ($failureCount -gt 0) { 'Warning' } else { 'Success' }
    Write-DebloatLog -Context $Context -Level $level -Component 'RegistryAction' -Message 'Accion de Registro procesada.' -Data @{ ActionId = $Action.Id; Title = $Action.Title; Warnings = $failureCount }
    return $failureCount
}

function Restore-DebloatRegistry {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $snapshotPath = Join-Path $Context.SessionPath 'registry.json'
    if (-not (Test-Path -LiteralPath $snapshotPath -PathType Leaf)) {
        Write-DebloatLog -Context $Context -Level Info -Component 'RegistryRestore' -Message 'La sesion no contiene valores de Registro para restaurar.' -Data @{}
        return
    }

    $records = @(Read-DebloatJson -Path $snapshotPath)
    for ($index = $records.Count - 1; $index -ge 0; $index--) {
        $record = $records[$index]
        if (-not (Test-Path -LiteralPath $record.Path)) {
            if (-not [bool]$record.Exists) {
                continue
            }
            New-Item -Path $record.Path -Force | Out-Null
        }

        $valueName = if ($record.Name -eq '@Default') { '' } else { [string]$record.Name }
        $key = Open-DebloatWritableRegistryKey -Path $record.Path
        try {
            if ([bool]$record.Exists) {
                $value = ConvertTo-RegistryValue -Value $record.Value -Type $record.Type
                $kind = [Microsoft.Win32.RegistryValueKind]::$($record.Type)
                $key.SetValue($valueName, $value, $kind)
            }
            else {
                $key.DeleteValue($valueName, $false)
            }
        }
        finally {
            $key.Dispose()
        }
        Write-DebloatLog -Context $Context -Level Success -Component 'RegistryRestore' -Message 'Valor de Registro restaurado.' -Data @{ Path = $record.Path; Name = $record.Name; Existed = [bool]$record.Exists }
    }
}

Export-ModuleMember -Function Invoke-DebloatRegistryAction, Restore-DebloatRegistry
