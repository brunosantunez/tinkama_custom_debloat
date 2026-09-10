[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $projectRoot 'src\Common.psm1')
Import-Module (Join-Path $projectRoot 'src\Worker.psm1')
Import-Module (Join-Path $projectRoot 'src\Execution.psm1')
Import-Module (Join-Path $projectRoot 'src\UserInterface.psm1')
$userPolicy = Get-ExecutionPolicy -Scope CurrentUser
$machinePolicy = Get-ExecutionPolicy -Scope LocalMachine
Enable-DebloatSessionScripts -ProjectRoot $projectRoot | Out-Null
if ((Get-ExecutionPolicy -Scope Process) -ne 'Bypass' -or
    (Get-ExecutionPolicy -Scope CurrentUser) -ne $userPolicy -or
    (Get-ExecutionPolicy -Scope LocalMachine) -ne $machinePolicy) {
    throw [InvalidOperationException]::new('La preparacion de scripts no quedo limitada al proceso.')
}
$outputRoot = Join-Path $projectRoot ('artifacts\ipc-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $outputRoot | Out-Null
$outputBase = Join-Path $outputRoot 'concurrent'
$job = Start-DebloatWorkerProcess -ScriptPath (Join-Path $PSScriptRoot 'Write-ProgressFixture.ps1') -ScriptArguments @('-OutputBasePath', ('"{0}"' -f $outputBase), '-Iterations', '600') -OutputBasePath $outputBase -WorkingDirectory $projectRoot
$reads = 0
$logReads = 0
$deadline = [DateTime]::UtcNow.AddSeconds(45)
try {
    while (-not $job.Process.HasExited) {
        if ([DateTime]::UtcNow -gt $deadline) {
            throw [TimeoutException]::new('El escritor de progreso no termino en 45 segundos.')
        }
        if (Test-Path -LiteralPath $job.ProgressPath -PathType Leaf) {
            $progress = Read-DebloatJson -Path $job.ProgressPath
            if ($progress.Current -lt 1 -or $progress.Current -gt $progress.Total) {
                throw [IO.InvalidDataException]::new('Se leyo un progreso incompleto o fuera de rango.')
            }
            $reads++
            if ('SessionPath' -in $progress.PSObject.Properties.Name -and
                -not [string]::IsNullOrWhiteSpace([string]$progress.SessionPath) -and
                (Test-Path -LiteralPath (Join-Path $progress.SessionPath 'operations.jsonl') -PathType Leaf)) {
                $formattedLog = Get-FormattedSessionLog -SessionPath $progress.SessionPath
                if ($formattedLog -match '\[Fixture\]') {
                    $logReads++
                }
            }
        }
    }
    $result = Read-DebloatWorkerResult -Job $job
    if (-not $result.Success -or $reads -lt 2 -or $logReads -lt 2) {
        throw [InvalidOperationException]::new("No se verifico lectura concurrente. Progreso: $reads; registro: $logReads")
    }
}
finally {
    if (-not $job.Process.HasExited) { $job.Process.Kill(); $job.Process.WaitForExit() }
    $job.Process.Dispose()
}

# Invalid requests stop before restore points or any system modification.
$requestPath = Join-Path $outputRoot 'empty-selection.json'
Save-DebloatJson -Path $requestPath -InputObject ([pscustomobject]@{ ActionIds = @(); ServiceIds = @() })
$job = Start-DebloatWorkerProcess -ScriptPath (Join-Path $projectRoot 'Invoke-Headless.ps1') -ScriptArguments @('-RequestPath', ('"{0}"' -f $requestPath)) -OutputBasePath $requestPath -WorkingDirectory $projectRoot
try {
    if (-not $job.Process.WaitForExit(30000)) { throw [TimeoutException]::new('El worker no rechazo la seleccion vacia en 30 segundos.') }
    $result = Read-DebloatWorkerResult -Job $job
    if ($result.Success -or $job.Process.ExitCode -eq 0 -or $result.SessionPath) {
        throw [InvalidOperationException]::new('El worker no rechazo correctamente la seleccion vacia.')
    }
    if ($result.ErrorType -notin @('System.ArgumentException', 'System.UnauthorizedAccessException')) {
        throw [InvalidOperationException]::new("Fallo inesperado al cargar el motor: $($result | ConvertTo-Json -Compress)")
    }
}
finally {
    if (-not $job.Process.HasExited) { $job.Process.Kill(); $job.Process.WaitForExit() }
    $job.Process.Dispose()
}
[pscustomobject]@{ ConcurrentReads = $reads; ConcurrentLogReads = $logReads; RejectedEmptySelection = $true; SessionOnlyExecutionPolicy = $true; SystemChangesApplied = $false } | Format-List
