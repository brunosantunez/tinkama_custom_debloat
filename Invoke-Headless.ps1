[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$RequestPath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$projectRoot = $PSScriptRoot
$resultPath = "$RequestPath.result.json"

try {
    Import-Module (Join-Path $projectRoot 'src\Common.psm1')
    if (-not (Test-Path -LiteralPath $RequestPath -PathType Leaf)) {
        throw [System.IO.FileNotFoundException]::new("No se encontro la solicitud de trabajo: $RequestPath")
    }

    $request = Get-Content -LiteralPath $RequestPath -Raw | ConvertFrom-Json
    if ($null -eq $request.ActionIds -or $null -eq $request.ServiceIds) {
        throw [System.IO.InvalidDataException]::new('La solicitud no contiene ActionIds y ServiceIds validos.')
    }

    Import-Module (Join-Path $projectRoot 'src\Catalog.psm1')
    Import-Module (Join-Path $projectRoot 'src\Engine.psm1')

    $catalog = Import-DebloatCatalog -Path (Join-Path $projectRoot 'config\catalog.json')
    $progressPath = "$RequestPath.progress.json"
    $progressCallback = {
        param([string]$Message, [int]$Current, [int]$Total, [string]$SessionPath)
        Save-DebloatJson -Path $progressPath -InputObject ([pscustomobject]@{
            Message = $Message
            Current = $Current
            Total = $Total
            SessionPath = $SessionPath
        })
    }

    $execution = Invoke-DebloatSelection `
        -ProjectRoot $projectRoot `
        -Catalog $catalog `
        -ActionIds ([string[]]$request.ActionIds) `
        -ServiceIds ([string[]]$request.ServiceIds) `
        -ProgressCallback $progressCallback

    $message = if ($execution.WarningCount -gt 0) {
        "Optimizacion finalizada con $($execution.WarningCount) advertencias. Revisa Depuracion y reinicia Windows."
    }
    else {
        'Optimizacion finalizada. Reinicia Windows para completar todos los cambios.'
    }
    [pscustomobject]@{
        Success = $true
        SessionPath = $execution.SessionPath
        DebugReportPath = $execution.DebugReportPath
        WarningCount = $execution.WarningCount
        Message = $message
    } | ConvertTo-Json | Set-Content -LiteralPath $resultPath -Encoding UTF8
    exit 0
}
catch {
    [pscustomobject]@{
        Success = $false
        SessionPath = $_.Exception.Data['SessionPath']
        DebugReportPath = $_.Exception.Data['DebugReportPath']
        Message = $_.Exception.Message
        ErrorType = $_.Exception.GetType().FullName
        Details = ($_ | Out-String)
        ScriptStackTrace = $_.ScriptStackTrace
    } | ConvertTo-Json | Set-Content -LiteralPath $resultPath -Encoding UTF8
    exit 1
}
