Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Common.psm1')
Import-Module (Join-Path $PSScriptRoot 'Execution.psm1')

function Start-DebloatWorkerProcess {
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath,
        [Parameter(Mandatory)]
        [string[]]$ScriptArguments,
        [Parameter(Mandatory)]
        [string]$OutputBasePath,
        [Parameter(Mandatory)]
        [string]$WorkingDirectory
    )

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        throw [System.IO.FileNotFoundException]::new("No se encontro el script de trabajo: $ScriptPath")
    }
    $arguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-STA', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $ScriptPath)) + $ScriptArguments
    $stderrPath = "$OutputBasePath.stderr.log"
    $stdoutPath = "$OutputBasePath.stdout.log"
    $process = Start-Process -FilePath (Get-DebloatPowerShellPath) -ArgumentList $arguments -WindowStyle Hidden -PassThru -WorkingDirectory $WorkingDirectory -RedirectStandardError $stderrPath -RedirectStandardOutput $stdoutPath
    # Retain the native handle so Windows PowerShell can read ExitCode after a short-lived child exits.
    $null = $process.Handle
    return [pscustomobject]@{
        Process = $process
        ResultPath = "$OutputBasePath.result.json"
        ProgressPath = "$OutputBasePath.progress.json"
        StandardErrorPath = $stderrPath
        StandardOutputPath = $stdoutPath
    }
}

function Read-DebloatWorkerResult {
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Job
    )

    if (-not $Job.Process.HasExited) {
        throw [System.InvalidOperationException]::new('El proceso de trabajo todavia esta activo.')
    }
    $Job.Process.WaitForExit()
    if (-not (Test-Path -LiteralPath $Job.ResultPath -PathType Leaf)) {
        $stderr = Get-Content -LiteralPath $Job.StandardErrorPath -Raw
        throw [System.InvalidOperationException]::new("El proceso termino con codigo $($Job.Process.ExitCode) sin generar resultado. Registro: $($Job.StandardErrorPath). $stderr")
    }
    $result = Read-DebloatJson -Path $Job.ResultPath
    foreach ($name in @('Success', 'Message', 'SessionPath')) {
        if ($name -notin $result.PSObject.Properties.Name) {
            throw [System.IO.InvalidDataException]::new("El resultado no contiene $name. Archivo: $($Job.ResultPath)")
        }
    }
    if ($result.Success -isnot [bool] -or $result.Message -isnot [string] -or [string]::IsNullOrWhiteSpace($result.Message)) {
        throw [System.IO.InvalidDataException]::new("El resultado contiene tipos invalidos. Archivo: $($Job.ResultPath)")
    }
    if ($result.Success -and $Job.Process.ExitCode -ne 0) {
        throw [System.InvalidOperationException]::new("El resultado indica exito pero el proceso termino con codigo $($Job.Process.ExitCode). Archivo: $($Job.ResultPath)")
    }
    return $result
}

Export-ModuleMember -Function Start-DebloatWorkerProcess, Read-DebloatWorkerResult
