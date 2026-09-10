Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Common.psm1')

function Save-SpecialSnapshot {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object]$Value
    )

    $snapshotPath = Join-Path $Context.SessionPath 'special.json'
    $records = @()
    if (Test-Path -LiteralPath $snapshotPath -PathType Leaf) {
        $records = @(Read-DebloatJson -Path $snapshotPath)
    }
    if (@($records | Where-Object Name -eq $Name).Count -gt 0) {
        return
    }

    $records += [pscustomobject]@{ Name = $Name; Value = $Value }
    Save-DebloatJson -InputObject ([object[]]$records) -Path $snapshotPath
}

function Get-ActivePowerSchemeGuid {
    [OutputType([string])]
    param()

    $result = Invoke-DebloatNativeCommand -FilePath 'powercfg.exe' -Arguments '/getactivescheme' -TimeoutSeconds 30 -AllowedExitCodes @(0)
    $match = [regex]::Match($result.StandardOutput, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
    if (-not $match.Success) {
        throw [System.InvalidOperationException]::new("No se pudo interpretar el plan de energia activo. Salida: $($result.StandardOutput)")
    }
    return $match.Value.ToLowerInvariant()
}

function Set-CustomPowerPlan {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $highPerformanceGuid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    $customGuid = 'f5e2b3cd-59a0-4f40-9de8-29a0f2a768b8'
    $activeGuid = Get-ActivePowerSchemeGuid
    $schemes = Invoke-DebloatNativeCommand -FilePath 'powercfg.exe' -Arguments '/list' -TimeoutSeconds 30 -AllowedExitCodes @(0)
    $customExisted = $schemes.StandardOutput -match [regex]::Escape($customGuid)
    Save-SpecialSnapshot -Context $Context -Name 'PowerPlan' -Value ([pscustomobject]@{ ActiveGuid = $activeGuid; CustomExisted = $customExisted; CustomGuid = $customGuid })

    if (-not $customExisted) {
        Invoke-DebloatNativeCommand -FilePath 'powercfg.exe' -Arguments "/duplicatescheme $highPerformanceGuid $customGuid" -TimeoutSeconds 30 -AllowedExitCodes @(0) | Out-Null
    }
    $renameArguments = '/changename {0} "Pulpo Custom - Alto rendimiento" "Plan estable para mantenimiento y uso diario"' -f $customGuid
    Invoke-DebloatNativeCommand -FilePath 'powercfg.exe' -Arguments $renameArguments -TimeoutSeconds 30 -AllowedExitCodes @(0) | Out-Null
    Invoke-DebloatNativeCommand -FilePath 'powercfg.exe' -Arguments "/setacvalueindex $customGuid SUB_PROCESSOR PROCTHROTTLEMIN 100" -TimeoutSeconds 30 -AllowedExitCodes @(0) | Out-Null
    Invoke-DebloatNativeCommand -FilePath 'powercfg.exe' -Arguments "/setdcvalueindex $customGuid SUB_PROCESSOR PROCTHROTTLEMIN 5" -TimeoutSeconds 30 -AllowedExitCodes @(0) | Out-Null
    Invoke-DebloatNativeCommand -FilePath 'powercfg.exe' -Arguments "/setacvalueindex $customGuid SUB_PROCESSOR PROCTHROTTLEMAX 100" -TimeoutSeconds 30 -AllowedExitCodes @(0) | Out-Null
    Invoke-DebloatNativeCommand -FilePath 'powercfg.exe' -Arguments "/setdcvalueindex $customGuid SUB_PROCESSOR PROCTHROTTLEMAX 100" -TimeoutSeconds 30 -AllowedExitCodes @(0) | Out-Null
    Invoke-DebloatNativeCommand -FilePath 'powercfg.exe' -Arguments "/setactive $customGuid" -TimeoutSeconds 30 -AllowedExitCodes @(0) | Out-Null
    Write-DebloatLog -Context $Context -Level Success -Component 'Power' -Message 'Plan personalizado creado y activado.' -Data @{ PreviousGuid = $activeGuid; CustomGuid = $customGuid }
}

function Clear-DebloatTemporaryFiles {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $requestedPaths = @(
        (Join-Path $env:SystemRoot 'Prefetch'),
        (Join-Path $env:SystemRoot 'Temp'),
        ([IO.Path]::GetTempPath().TrimEnd('\'))
    ) | Select-Object -Unique
    $allowedPaths = @($requestedPaths | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') })
    $deleted = 0
    $failures = [System.Collections.Generic.List[string]]::new()

    foreach ($requestedPath in $requestedPaths) {
        $resolvedPath = [IO.Path]::GetFullPath($requestedPath).TrimEnd('\')
        if ($resolvedPath -notin $allowedPaths -or -not [IO.Path]::IsPathRooted($resolvedPath)) {
            throw [System.UnauthorizedAccessException]::new("Ruta de limpieza fuera de alcance: $resolvedPath")
        }
        if (-not (Test-Path -LiteralPath $resolvedPath -PathType Container)) {
            Write-DebloatLog -Context $Context -Level Info -Component 'Cleanup' -Message 'La carpeta de limpieza no existe.' -Data @{ Path = $resolvedPath }
            continue
        }

        foreach ($item in @(Get-ChildItem -LiteralPath $resolvedPath -Force)) {
            try {
                Remove-Item -LiteralPath $item.FullName -Recurse -Force
                $deleted++
            }
            catch {
                $failures.Add("$($item.FullName): $($_.Exception.Message)")
            }
        }
    }

    $level = if ($failures.Count -gt 0) { 'Warning' } else { 'Success' }
    Write-DebloatLog -Context $Context -Level $level -Component 'Cleanup' -Message 'Limpieza de temporales finalizada.' -Data @{ DeletedEntries = $deleted; SkippedEntries = $failures.Count; Failures = [string[]]$failures }
}

function Disable-DebloatHibernation {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'
    if (-not (Test-Path -LiteralPath $path)) {
        throw [System.InvalidOperationException]::new('No se puede determinar el estado original de hibernacion: falta Control\\Power.')
    }
    $key = Get-Item -LiteralPath $path
    if ('HibernateEnabled' -notin $key.GetValueNames()) {
        throw [System.InvalidOperationException]::new('No se puede determinar el estado original de hibernacion: falta HibernateEnabled.')
    }
    $value = [int]$key.GetValue('HibernateEnabled')
    Save-SpecialSnapshot -Context $Context -Name 'Hibernation' -Value $value
    Invoke-DebloatNativeCommand -FilePath 'powercfg.exe' -Arguments '/hibernate off' -TimeoutSeconds 30 -AllowedExitCodes @(0) | Out-Null
    Write-DebloatLog -Context $Context -Level Success -Component 'Power' -Message 'Hibernacion desactivada.' -Data @{ PreviousValue = $value }
}

function Disable-DebloatReservedStorage {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $state = Get-WindowsReservedStorageState
    Save-SpecialSnapshot -Context $Context -Name 'ReservedStorage' -Value ([string]$state.ReservedStorageState)
    if ($state.ReservedStorageState -ne 'Disabled') {
        Set-WindowsReservedStorageState -State Disabled | Out-Null
    }
    Write-DebloatLog -Context $Context -Level Success -Component 'Storage' -Message 'Almacenamiento reservado desactivado.' -Data @{ PreviousState = [string]$state.ReservedStorageState }
}

function Get-OneDriveSetupPath {
    [OutputType([string])]
    param()

    $candidates = @(
        (Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe'),
        (Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\Update\OneDriveSetup.exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }
    throw [System.IO.FileNotFoundException]::new('No se encontro OneDriveSetup.exe para ejecutar el desinstalador oficial.')
}

function Remove-DebloatOneDrive {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $installCandidates = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft OneDrive\OneDrive.exe')
    )
    $installed = @($installCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }).Count -gt 0
    if (-not $installed) {
        Write-DebloatLog -Context $Context -Level Info -Component 'OneDrive' -Message 'OneDrive no esta instalado en las ubicaciones admitidas.' -Data @{ Paths = $installCandidates }
        return
    }
    $setupPath = Get-OneDriveSetupPath
    Save-SpecialSnapshot -Context $Context -Name 'OneDrive' -Value ([pscustomobject]@{ WasInstalled = $true; SetupPath = $setupPath })

    foreach ($process in @(Get-CimInstance -ClassName Win32_Process -Filter "Name='OneDrive.exe'")) {
        Stop-Process -Id $process.ProcessId -Force
    }
    Invoke-DebloatNativeCommand -FilePath $setupPath -Arguments '/uninstall' -TimeoutSeconds 180 -AllowedExitCodes @(0) | Out-Null
    Write-DebloatLog -Context $Context -Level Success -Component 'OneDrive' -Message 'Desinstalador oficial de OneDrive ejecutado.' -Data @{ SetupPath = $setupPath; UserFilesDeleted = $false }
}

function Disable-DebloatRecall {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $feature = @(Get-WindowsOptionalFeature -Online | Where-Object FeatureName -eq 'Recall')
    if ($feature.Count -eq 0) {
        Write-DebloatLog -Context $Context -Level Info -Component 'Recall' -Message 'La caracteristica opcional Recall no existe en esta compilacion.' -Data @{}
        return
    }
    Save-SpecialSnapshot -Context $Context -Name 'Recall' -Value ([string]$feature[0].State)
    if ($feature[0].State -eq 'Enabled') {
        Disable-WindowsOptionalFeature -FeatureName 'Recall' -Online -NoRestart | Out-Null
    }
    Write-DebloatLog -Context $Context -Level Success -Component 'Recall' -Message 'Caracteristica Recall deshabilitada.' -Data @{ PreviousState = [string]$feature[0].State }
}

function Disable-DebloatTelemetryTasks {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $targetPaths = @(
        '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
        '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
        '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
        '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
        '\Microsoft\Windows\Feedback\Siuf\DmClient',
        '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
        '\Microsoft\Windows\Windows Error Reporting\QueueReporting'
    )
    $allTasks = @(Get-ScheduledTask)
    $snapshots = [System.Collections.Generic.List[object]]::new()

    foreach ($targetPath in $targetPaths) {
        $task = @($allTasks | Where-Object { "$($_.TaskPath)$($_.TaskName)" -eq $targetPath })
        if ($task.Count -eq 0) {
            Write-DebloatLog -Context $Context -Level Info -Component 'TelemetryTasks' -Message 'La tarea programada no existe en esta compilacion.' -Data @{ Task = $targetPath }
            continue
        }
        $snapshots.Add([pscustomobject]@{ TaskPath = $task[0].TaskPath; TaskName = $task[0].TaskName; State = [string]$task[0].State })
    }

    Save-SpecialSnapshot -Context $Context -Name 'TelemetryTasks' -Value ([object[]]$snapshots)
    foreach ($snapshot in $snapshots) {
        $task = Get-ScheduledTask -TaskPath $snapshot.TaskPath -TaskName $snapshot.TaskName
        if ($task.State -ne 'Disabled') {
            Disable-ScheduledTask -InputObject $task | Out-Null
        }
        Write-DebloatLog -Context $Context -Level Success -Component 'TelemetryTasks' -Message 'Tarea de telemetria deshabilitada.' -Data @{ TaskPath = $snapshot.TaskPath; TaskName = $snapshot.TaskName; PreviousState = $snapshot.State }
    }
}

function Invoke-DebloatSpecialAction {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context,

        [Parameter(Mandatory)]
        [pscustomobject]$Action
    )

    switch ($Action.Handler) {
        'SetCustomPowerPlan' { Set-CustomPowerPlan -Context $Context }
        'CleanTemporaryFiles' { Clear-DebloatTemporaryFiles -Context $Context }
        'DisableHibernation' { Disable-DebloatHibernation -Context $Context }
        'DisableReservedStorage' { Disable-DebloatReservedStorage -Context $Context }
        'RemoveOneDrive' { Remove-DebloatOneDrive -Context $Context }
        'DisableRecall' { Disable-DebloatRecall -Context $Context }
        'DisableTelemetryTasks' { Disable-DebloatTelemetryTasks -Context $Context }
        default { throw [System.InvalidOperationException]::new("Handler especial no admitido: $($Action.Handler)") }
    }
}

function Restore-DebloatSpecialState {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $snapshotPath = Join-Path $Context.SessionPath 'special.json'
    if (-not (Test-Path -LiteralPath $snapshotPath -PathType Leaf)) {
        Write-DebloatLog -Context $Context -Level Info -Component 'SpecialRestore' -Message 'La sesion no contiene estados especiales para restaurar.' -Data @{}
        return
    }

    $records = @(Read-DebloatJson -Path $snapshotPath)
    for ($index = $records.Count - 1; $index -ge 0; $index--) {
        $record = $records[$index]
        switch ($record.Name) {
            'PowerPlan' {
                Invoke-DebloatNativeCommand -FilePath 'powercfg.exe' -Arguments "/setactive $($record.Value.ActiveGuid)" -TimeoutSeconds 30 -AllowedExitCodes @(0) | Out-Null
                if (-not [bool]$record.Value.CustomExisted) {
                    Invoke-DebloatNativeCommand -FilePath 'powercfg.exe' -Arguments "/delete $($record.Value.CustomGuid)" -TimeoutSeconds 30 -AllowedExitCodes @(0) | Out-Null
                }
            }
            'Hibernation' {
                $state = if ([int]$record.Value -eq 0) { 'off' } else { 'on' }
                Invoke-DebloatNativeCommand -FilePath 'powercfg.exe' -Arguments "/hibernate $state" -TimeoutSeconds 30 -AllowedExitCodes @(0) | Out-Null
            }
            'ReservedStorage' {
                $state = [string]$record.Value
                Set-WindowsReservedStorageState -State $state | Out-Null
            }
            'OneDrive' {
                if ([bool]$record.Value.WasInstalled) {
                    if (-not (Test-Path -LiteralPath $record.Value.SetupPath -PathType Leaf)) {
                        throw [System.IO.FileNotFoundException]::new("No se puede reinstalar OneDrive; falta $($record.Value.SetupPath)")
                    }
                    Invoke-DebloatNativeCommand -FilePath $record.Value.SetupPath -Arguments '/install' -TimeoutSeconds 180 -AllowedExitCodes @(0) | Out-Null
                }
            }
            'Recall' {
                if ($record.Value -eq 'Enabled') {
                    Enable-WindowsOptionalFeature -FeatureName 'Recall' -Online -NoRestart | Out-Null
                }
            }
            'TelemetryTasks' {
                foreach ($taskState in @($record.Value)) {
                    $task = @(Get-ScheduledTask | Where-Object { $_.TaskPath -eq $taskState.TaskPath -and $_.TaskName -eq $taskState.TaskName })
                    if ($task.Count -eq 0) {
                        Write-DebloatLog -Context $Context -Level Warning -Component 'SpecialRestore' -Message 'La tarea de telemetria respaldada ya no existe.' -Data @{ TaskPath = $taskState.TaskPath; TaskName = $taskState.TaskName }
                        continue
                    }
                    if ($taskState.State -ne 'Disabled') {
                        Enable-ScheduledTask -InputObject $task[0] | Out-Null
                    }
                }
            }
            default {
                throw [System.InvalidOperationException]::new("Estado especial desconocido durante la restauracion: $($record.Name)")
            }
        }
        Write-DebloatLog -Context $Context -Level Success -Component 'SpecialRestore' -Message 'Estado especial restaurado.' -Data @{ Name = $record.Name }
    }
}

Export-ModuleMember -Function Invoke-DebloatSpecialAction, Restore-DebloatSpecialState
