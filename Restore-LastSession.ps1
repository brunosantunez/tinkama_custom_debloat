[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ResultPath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$projectRoot = $PSScriptRoot

try {
    Import-Module (Join-Path $projectRoot 'src\Engine.psm1')
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
        Details = ($_ | Out-String)
        ScriptStackTrace = $_.ScriptStackTrace
    } | ConvertTo-Json | Set-Content -LiteralPath $resultPath -Encoding UTF8
    exit 1
}
