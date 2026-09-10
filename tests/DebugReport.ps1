[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $projectRoot 'src\Common.psm1')

$sessionPath = Join-Path $projectRoot ('artifacts\debug-' + [Guid]::NewGuid().ToString('N'))
$context = New-DebloatContext -SessionPath $sessionPath

try {
    Write-DebloatLog -Context $context -Level Success -Component 'Fixture' -Message 'Cambio aplicado.' -Data @{ ActionId = 'success' }
    Write-DebloatNotApplied -Context $context -Level Info -Component 'Packages' -Instruction 'Eliminar paquete Microsoft.Test' -Command "Get-AppxPackage -Name 'Microsoft.Test'" -Reason 'El paquete no esta instalado.' -Data @{ ActionId = 'missing_package' }
    Write-DebloatNotApplied -Context $context -Level Warning -Component 'Registry' -Instruction 'Establecer un valor de prueba' -Command 'reg.exe add "HKCU\Software\PulpoTest" /v Test /t REG_DWORD /d 1 /f' -Reason 'Acceso denegado de prueba.' -Data @{ ActionId = 'registry_failure' }

    $report = Get-DebloatDebugReport -SessionPath $sessionPath
    if ($report.Count -ne 2 -or
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
        InstructionsIncluded = $true
        CommandsIncluded = $true
        ReasonsIncluded = $true
        ReportSaved = $true
    } | Format-List
}
finally {
    if (Test-Path -LiteralPath $sessionPath) {
        Remove-Item -LiteralPath $sessionPath -Recurse -Force
    }
}
