[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $projectRoot 'src\Common.psm1')

$powershellPath = Join-Path $PSHOME 'powershell.exe'
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$timeoutObserved = $false
try {
    Invoke-DebloatNativeCommand -FilePath $powershellPath -Arguments '-NoLogo -NoProfile -NonInteractive -Command "Start-Sleep -Seconds 10"' -TimeoutSeconds 1 -AllowedExitCodes @(0) | Out-Null
}
catch [System.TimeoutException] {
    $timeoutObserved = $true
}
finally {
    $stopwatch.Stop()
}

if (-not $timeoutObserved -or $stopwatch.Elapsed.TotalSeconds -ge 5) {
    throw [System.TimeoutException]::new("El proceso de prueba no respeto el timeout. Duracion: $($stopwatch.Elapsed.TotalSeconds) segundos.")
}

[pscustomobject]@{
    TimeoutObserved = $timeoutObserved
    CompletedUnderFiveSeconds = $true
    ElapsedMilliseconds = [int]$stopwatch.Elapsed.TotalMilliseconds
} | Format-List
