[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $projectRoot 'src\Common.psm1')
Import-Module (Join-Path $projectRoot 'src\Registry.psm1')
Import-Module (Join-Path $projectRoot 'src\Catalog.psm1')
$catalog = Import-DebloatCatalog -Path (Join-Path $projectRoot 'config\catalog.json')
$testId = [Guid]::NewGuid().ToString('N')
$root = "HKCU:\Software\PulpoCustomDebloat\Tests\$testId"
$context = New-DebloatContext -SessionPath (Join-Path $projectRoot "artifacts\privacy-$testId")
$count = 0
try {
    foreach ($action in @($catalog.Actions | Where-Object Id -in @('privacy_app_permissions', 'privacy_background_apps', 'privacy_diagnostics'))) {
        $operations = foreach ($operation in $action.Registry) {
            $path = Join-Path $root ([string]$count++)
            New-Item -Path $path -Force | Out-Null
            # Seed a real per-app exception to verify empty REG_MULTI_SZ and rollback.
            New-ItemProperty -LiteralPath $path -Name $operation.Name -PropertyType MultiString -Value @('Original.Package_family') | Out-Null
            [pscustomobject]@{ Path = $path; Name = $operation.Name; Type = $operation.Type; Value = $operation.Value }
        }
        $isolated = [pscustomobject]@{ Id = $action.Id; Title = $action.Title; Registry = @($operations) }
        if ((Invoke-DebloatRegistryAction -Context $context -Action $isolated) -ne 0) {
            throw [System.InvalidOperationException]::new("Fallo la escritura de $($action.Id). Sesion: $($context.SessionPath)")
        }
    }
    Restore-DebloatRegistry -Context $context
    foreach ($record in @(Read-DebloatJson -Path (Join-Path $context.SessionPath 'registry.json'))) {
        $key = Get-Item -LiteralPath $record.Path
        try {
            if ($key.GetValueKind($record.Name) -ne 'MultiString' -or
                ($key.GetValue($record.Name) -join ',') -ne 'Original.Package_family') {
                throw [System.IO.InvalidDataException]::new("No se restauro la excepcion en $($record.Path).")
            }
        }
        finally { $key.Dispose() }
    }
    [pscustomobject]@{ OperationsVerified = $count; Restored = $true; SessionPath = $context.SessionPath }
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
