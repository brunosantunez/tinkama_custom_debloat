[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $projectRoot 'src\Common.psm1')
Import-Module (Join-Path $projectRoot 'src\Packages.psm1')

$testId = [Guid]::NewGuid().ToString('N')
$sessionPath = Join-Path ([System.IO.Path]::GetTempPath()) "PulpoCustomDebloat-Packages-$testId"
$context = New-DebloatContext -SessionPath $sessionPath
$action = [pscustomobject]@{
    Id = 'PackageContinuation'
    Title = 'Package continuation test'
    PackagePatterns = [string[]]@('Invalid!First', 'Invalid!Second')
}

try {
    $warningCount = Invoke-DebloatPackageAction -Context $context -Action $action
    $entries = @(Get-Content -LiteralPath $context.LogPath | ForEach-Object { $_ | ConvertFrom-Json })
    $firstWarning = @($entries | Where-Object {
        $_.Level -eq 'Warning' -and 'Pattern' -in $_.Data.PSObject.Properties.Name -and $_.Data.Pattern -eq 'Invalid!First'
    })
    $secondWarning = @($entries | Where-Object {
        $_.Level -eq 'Warning' -and 'Pattern' -in $_.Data.PSObject.Properties.Name -and $_.Data.Pattern -eq 'Invalid!Second'
    })
    if ($warningCount -ne 2 -or
        $firstWarning.Count -ne 1 -or
        $secondWarning.Count -ne 1 -or
        $firstWarning[0].Data.Outcome -ne 'NotApplied' -or
        [string]::IsNullOrWhiteSpace([string]$firstWarning[0].Data.Instruction) -or
        [string]::IsNullOrWhiteSpace([string]$firstWarning[0].Data.Command) -or
        [string]::IsNullOrWhiteSpace([string]$firstWarning[0].Data.Reason)) {
        throw [System.InvalidOperationException]::new('Un patron fallido impidio continuar con el siguiente patron de paquete.')
    }

    [pscustomobject]@{
        WarningRecorded = $true
        DiagnosticDataRecorded = $true
        NextPatternProcessed = $true
        PackagesRemoved = $false
    } | Format-List
}
finally {
    if (Test-Path -LiteralPath $sessionPath -PathType Container) {
        Remove-Item -LiteralPath $sessionPath -Recurse -Force
    }
}
