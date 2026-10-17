[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $projectRoot 'src\Common.psm1')

$sessionPath = Join-Path $projectRoot ('artifacts\debug-' + [Guid]::NewGuid().ToString('N'))
$context = New-DebloatContext -SessionPath $sessionPath
$lockJob = $null

try {
    New-Item -ItemType Directory -Path $sessionPath -Force | Out-Null
    $lockReadyPath = Join-Path $sessionPath 'log-lock-ready'
    $lockJob = Start-Job -ArgumentList $context.LogPath, $lockReadyPath -ScriptBlock {
        param([string]$LogPath, [string]$ReadyPath)
        $stream = [System.IO.FileStream]::new(
            $LogPath,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )
        try {
            [System.IO.File]::WriteAllText($ReadyPath, 'ready')
            Start-Sleep -Milliseconds 350
        }
        finally {
            $stream.Dispose()
        }
    }
    $lockDeadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $lockReadyPath -PathType Leaf)) {
        if ($lockJob.State -in @('Failed', 'Stopped') -or [DateTime]::UtcNow -ge $lockDeadline) {
            throw [System.TimeoutException]::new('No se pudo iniciar el bloqueo temporal del registro para la prueba.')
        }
        Start-Sleep -Milliseconds 20
    }
    $writeStartedUtc = [DateTime]::UtcNow
    Write-DebloatLog -Context $context -Level Success -Component 'Fixture' -Message 'Cambio aplicado.' -Data @{ ActionId = 'success' }
    $writeWait = [DateTime]::UtcNow - $writeStartedUtc
    if ($writeWait.TotalMilliseconds -lt 100) {
        throw [System.InvalidOperationException]::new('La escritura no espero el bloqueo exclusivo temporal del registro.')
    }
    Write-DebloatNotApplied -Context $context -Level Info -Component 'Packages' -Instruction 'Eliminar paquete Microsoft.Test' -Command "Get-AppxPackage -Name 'Microsoft.Test'" -Reason 'El paquete no esta instalado.' -Data @{ ActionId = 'missing_package' }
    Write-DebloatNotApplied -Context $context -Level Warning -Component 'Registry' -Instruction 'Establecer un valor de prueba' -Command 'reg.exe add "HKCU\Software\TinkamaTest" /v Test /t REG_DWORD /d 1 /f' -Reason 'Acceso denegado de prueba.' -Data @{ ActionId = 'registry_failure' }

    $lockReadyPath = Join-Path $sessionPath 'persistent-log-lock-ready'
    $lockJob = Start-Job -ArgumentList $context.LogPath, $lockReadyPath -ScriptBlock {
        param([string]$LogPath, [string]$ReadyPath)
        $stream = [System.IO.FileStream]::new(
            $LogPath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )
        try {
            [System.IO.File]::WriteAllText($ReadyPath, 'ready')
            Start-Sleep -Seconds 10
        }
        finally {
            $stream.Dispose()
        }
    }
    $lockDeadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $lockReadyPath -PathType Leaf)) {
        if ($lockJob.State -in @('Failed', 'Stopped') -or [DateTime]::UtcNow -ge $lockDeadline) {
            throw [System.TimeoutException]::new('No se pudo mantener el bloqueo exclusivo del registro para la prueba de respaldo.')
        }
        Start-Sleep -Milliseconds 20
    }
    Write-DebloatNotApplied -Context $context -Level Warning -Component 'Engine' -Instruction 'Continuar tras bloqueo de registro' -Command 'Write-DebloatNotApplied' -Reason 'El registro principal esta bloqueado.' -Data @{ ActionId = 'persistent_log_lock' }
    Stop-Job -Job $lockJob
    Receive-Job -Job $lockJob -ErrorAction SilentlyContinue | Out-Null
    Remove-Job -Job $lockJob -Force
    $lockJob = $null

    $report = Get-DebloatDebugReport -SessionPath $sessionPath
    if ($report.Count -ne 3 -or
        $report.Text -notmatch 'Instruccion: Eliminar paquete Microsoft\.Test' -or
        $report.Text -notmatch "Comando: Get-AppxPackage -Name 'Microsoft\.Test'" -or
        $report.Text -notmatch 'Motivo: Acceso denegado de prueba\.' -or
        $report.Text -match 'Cambio aplicado') {
        throw [System.IO.InvalidDataException]::new("El informe de depuracion no conserva las incidencias esperadas.`n$($report.Text)")
    }

    $reportPath = Save-DebloatDebugReport -SessionPath $sessionPath
    $savedText = Get-Content -LiteralPath $reportPath -Raw
    if ($savedText -ne ($report.Text + [Environment]::NewLine)) {
        throw [System.IO.InvalidDataException]::new('El archivo de depuracion no coincide con el informe generado.')
    }

    [pscustomobject]@{
        DiagnosticEntries = $report.Count
        WriterWaitedForLock = $true
        PersistentLockFallbackIncluded = $true
        InstructionsIncluded = $true
        CommandsIncluded = $true
        ReasonsIncluded = $true
        ReportSaved = $true
    } | Format-List
}
finally {
    if ($null -ne $lockJob) {
        if ($lockJob.State -eq 'Running') {
            Stop-Job -Job $lockJob
        }
        Receive-Job -Job $lockJob -ErrorAction SilentlyContinue | Out-Null
        Remove-Job -Job $lockJob -Force
    }
    if (Test-Path -LiteralPath $sessionPath) {
        Remove-Item -LiteralPath $sessionPath -Recurse -Force
    }
}
