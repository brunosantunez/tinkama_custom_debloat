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
    if (-not (Test-Path -LiteralPath $RequestPath -PathType Leaf)) {
        throw [System.IO.FileNotFoundException]::new("No se encontro la solicitud de trabajo: $RequestPath")
    }

    $request = Get-Content -LiteralPath $RequestPath -Raw | ConvertFrom-Json
    if ($null -eq $request.ActionIds -or $null -eq $request.ServiceIds) {
        throw [System.IO.InvalidDataException]::new('La solicitud no contiene ActionIds y ServiceIds validos.')
    }

    Import-Module (Join-Path $projectRoot 'src\Catalog.psm1') -Force
    Import-Module (Join-Path $projectRoot 'src\Engine.psm1') -Force

    $catalog = Import-DebloatCatalog -Path (Join-Path $projectRoot 'config\catalog.json')
    $progressPath = "$RequestPath.progress.json"
    $progressCallback = {
        param([string]$Message, [int]$Current, [int]$Total)
        [pscustomobject]@{
            Message = $Message
            Current = $Current
            Total = $Total
        } | ConvertTo-Json | Set-Content -LiteralPath $progressPath -Encoding UTF8
    }

    $sessionPath = Invoke-DebloatSelection `
        -ProjectRoot $projectRoot `
        -Catalog $catalog `
        -ActionIds ([string[]]$request.ActionIds) `
        -ServiceIds ([string[]]$request.ServiceIds) `
        -ProgressCallback $progressCallback

    [pscustomobject]@{
        Success = $true
        SessionPath = $sessionPath
        Message = 'Optimizacion finalizada. Reinicia Windows para completar todos los cambios.'
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
