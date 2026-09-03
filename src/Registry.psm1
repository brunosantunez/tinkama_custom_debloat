Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force

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

    $key = Get-Item -LiteralPath $Operation.Path
    $valueName = if ($Operation.Name -eq '@Default') { '' } else { [string]$Operation.Name }
    $value = ConvertTo-RegistryValue -Value $Operation.Value -Type $Operation.Type
    $kind = [Microsoft.Win32.RegistryValueKind]::$($Operation.Type)
    $key.SetValue($valueName, $value, $kind)
    Write-DebloatLog -Context $Context -Level Info -Component 'Registry' -Message 'Valor de Registro aplicado.' -Data @{ ActionId = $ActionId; Path = $Operation.Path; Name = $Operation.Name; Type = $Operation.Type; Value = $Operation.Value }
}

function Invoke-DebloatRegistryAction {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context,

        [Parameter(Mandatory)]
        [pscustomobject]$Action
    )

    foreach ($operation in @($Action.Registry)) {
        Set-DebloatRegistryValue -Context $Context -ActionId $Action.Id -Operation $operation
    }
    Write-DebloatLog -Context $Context -Level Success -Component 'RegistryAction' -Message 'Accion de Registro completada.' -Data @{ ActionId = $Action.Id; Title = $Action.Title }
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

        $key = Get-Item -LiteralPath $record.Path
        $valueName = if ($record.Name -eq '@Default') { '' } else { [string]$record.Name }
        if ([bool]$record.Exists) {
            $value = ConvertTo-RegistryValue -Value $record.Value -Type $record.Type
            $kind = [Microsoft.Win32.RegistryValueKind]::$($record.Type)
            $key.SetValue($valueName, $value, $kind)
        }
        else {
            $key.DeleteValue($valueName, $false)
        }
        Write-DebloatLog -Context $Context -Level Success -Component 'RegistryRestore' -Message 'Valor de Registro restaurado.' -Data @{ Path = $record.Path; Name = $record.Name; Existed = [bool]$record.Exists }
    }
}

Export-ModuleMember -Function Invoke-DebloatRegistryAction, Restore-DebloatRegistry
