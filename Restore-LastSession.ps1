[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$projectRoot = $PSScriptRoot
$resultPath = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'PulpoCustomDebloat\restore-result.json'

try {
    Import-Module (Join-Path $projectRoot 'src\Engine.psm1') -Force
    $restoredPath = Restore-LatestDebloatSession -ProjectRoot $projectRoot
    [pscustomobject]@{
        Success = $true
        SessionPath = $restoredPath
        Message = 'Se restauraron registro, servicios y plan de energia. Usa Restaurar sistema para recuperar aplicaciones eliminadas.'
    } | ConvertTo-Json | Set-Content -LiteralPath $resultPath -Encoding UTF8
    exit 0
}
catch {
    [pscustomobject]@{
        Success = $false
        SessionPath = $null
        Message = $_.Exception.Message
        ErrorType = $_.Exception.GetType().FullName
    } | ConvertTo-Json | Set-Content -LiteralPath $resultPath -Encoding UTF8
    exit 1
}
