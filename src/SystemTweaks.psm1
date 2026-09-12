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
    [OutputType([int])]
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
            $pathLiteral = ConvertTo-DebloatPowerShellLiteral -Value (Join-Path $resolvedPath '*')
            Write-DebloatNotApplied -Context $Context -Level Info -Component 'Cleanup' -Instruction "Vaciar la carpeta temporal $resolvedPath" -Command "Remove-Item -LiteralPath $pathLiteral -Recurse -Force" -Reason 'La carpeta de limpieza no existe.' -Data @{ Path = $resolvedPath }
            continue
        }

        foreach ($item in @(Get-ChildItem -LiteralPath $resolvedPath -Force)) {
            try {
                Remove-Item -LiteralPath $item.FullName -Recurse -Force
                $deleted++
            }
            catch {
                $failures.Add("$($item.FullName): $($_.Exception.Message)")
                $pathLiteral = ConvertTo-DebloatPowerShellLiteral -Value $item.FullName
                Write-DebloatNotApplied -Context $Context -Level Warning -Component 'Cleanup' -Instruction "Eliminar el elemento temporal $($item.FullName)" -Command "Remove-Item -LiteralPath $pathLiteral -Recurse -Force" -Reason $_.Exception.Message -Data @{ Path = $item.FullName }
            }
        }
    }

    $level = if ($failures.Count -gt 0) { 'Warning' } else { 'Success' }
    Write-DebloatLog -Context $Context -Level $level -Component 'Cleanup' -Message 'Limpieza de temporales finalizada.' -Data @{ DeletedEntries = $deleted; SkippedEntries = $failures.Count; Failures = [string[]]$failures }
    return $failures.Count
}

function Disable-DebloatHibernation {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'
    $registryValueExists = $false
    $registryValue = $null
    if (Test-Path -LiteralPath $path) {
        $key = Get-Item -LiteralPath $path
        try {
            if ('HibernateEnabled' -in $key.GetValueNames()) {
                $registryValueExists = $true
                $registryValue = [int]$key.GetValue('HibernateEnabled')
            }
        }
        finally {
            $key.Dispose()
        }
    }
    $hiberfilePath = Join-Path $env:SystemDrive 'hiberfil.sys'
    $wasEnabled = if ($registryValueExists) { $registryValue -ne 0 } else { [System.IO.File]::Exists($hiberfilePath) }
    Save-SpecialSnapshot -Context $Context -Name 'Hibernation' -Value ([pscustomobject]@{
        WasEnabled = $wasEnabled
        RegistryValueExisted = $registryValueExists
        RegistryValue = $registryValue
    })
    Invoke-DebloatNativeCommand -FilePath 'powercfg.exe' -Arguments '/hibernate off' -TimeoutSeconds 30 -AllowedExitCodes @(0) | Out-Null
    $previousState = if ($wasEnabled) { 'Enabled' } else { 'Disabled' }
    Write-DebloatLog -Context $Context -Level Success -Component 'Power' -Message 'Hibernacion desactivada.' -Data @{ PreviousState = $previousState; RegistryValueExisted = $registryValueExists }
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
        Write-DebloatNotApplied -Context $Context -Level Info -Component 'OneDrive' -Instruction 'Desinstalar OneDrive mediante su instalador oficial' -Command 'OneDriveSetup.exe /uninstall' -Reason 'OneDrive no esta instalado en las ubicaciones admitidas.' -Data @{ Paths = $installCandidates }
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
        Write-DebloatNotApplied -Context $Context -Level Info -Component 'Recall' -Instruction 'Deshabilitar la caracteristica opcional Recall' -Command "Disable-WindowsOptionalFeature -FeatureName 'Recall' -Online -NoRestart" -Reason 'La caracteristica opcional Recall no existe en esta compilacion.' -Data @{}
        return
    }
    Save-SpecialSnapshot -Context $Context -Name 'Recall' -Value ([string]$feature[0].State)
    if ($feature[0].State -eq 'Enabled') {
        Disable-WindowsOptionalFeature -FeatureName 'Recall' -Online -NoRestart | Out-Null
    }
    Write-DebloatLog -Context $Context -Level Success -Component 'Recall' -Message 'Caracteristica Recall deshabilitada.' -Data @{ PreviousState = [string]$feature[0].State }
}

function Disable-DebloatTelemetryTasks {
    [OutputType([int])]
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
        '\Microsoft\Windows\Windows Error Reporting\QueueReporting',
        '\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask',
        '\Microsoft\Windows\Autochk\Proxy',
        '\Microsoft\Windows\Diagnosis\Scheduled',
        '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
        '\Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem',
        '\Microsoft\Windows\RAC\RacTask',
        '\Microsoft\Windows\WDI\ResolutionHost'
    )
    $allTasks = @(Get-ScheduledTask)
    $snapshots = [System.Collections.Generic.List[object]]::new()

    foreach ($targetPath in $targetPaths) {
        $task = @($allTasks | Where-Object { "$($_.TaskPath)$($_.TaskName)" -eq $targetPath })
        if ($task.Count -eq 0) {
            $taskLiteral = ConvertTo-DebloatPowerShellLiteral -Value $targetPath
            $command = "Get-ScheduledTask | Where-Object { `"`$(`$_.TaskPath)`$(`$_.TaskName)`" -eq $taskLiteral } | Disable-ScheduledTask"
            Write-DebloatNotApplied -Context $Context -Level Info -Component 'TelemetryTasks' -Instruction "Deshabilitar la tarea programada $targetPath" -Command $command -Reason 'La tarea programada no existe en esta compilacion.' -Data @{ Task = $targetPath }
            continue
        }
        $snapshots.Add([pscustomobject]@{ TaskPath = $task[0].TaskPath; TaskName = $task[0].TaskName; State = [string]$task[0].State })
    }

    Save-SpecialSnapshot -Context $Context -Name 'TelemetryTasks' -Value ([object[]]$snapshots)
    $failureCount = 0
    foreach ($snapshot in $snapshots) {
        $taskPathLiteral = ConvertTo-DebloatPowerShellLiteral -Value $snapshot.TaskPath
        $taskNameLiteral = ConvertTo-DebloatPowerShellLiteral -Value $snapshot.TaskName
        $command = "Disable-ScheduledTask -TaskPath $taskPathLiteral -TaskName $taskNameLiteral"
        try {
            $task = Get-ScheduledTask -TaskPath $snapshot.TaskPath -TaskName $snapshot.TaskName
            if ($task.Settings.Enabled) {
                Disable-ScheduledTask -TaskPath $snapshot.TaskPath -TaskName $snapshot.TaskName | Out-Null
                $task = Get-ScheduledTask -TaskPath $snapshot.TaskPath -TaskName $snapshot.TaskName
            }
            if ($task.Settings.Enabled) {
                throw [System.InvalidOperationException]::new('La tarea continua habilitada despues de ejecutar Disable-ScheduledTask.')
            }
            Write-DebloatLog -Context $Context -Level Success -Component 'TelemetryTasks' -Message 'Tarea de telemetria deshabilitada.' -Data @{ TaskPath = $snapshot.TaskPath; TaskName = $snapshot.TaskName; PreviousState = $snapshot.State; Command = $command }
        }
        catch {
            $failureCount++
            Write-DebloatNotApplied -Context $Context -Level Warning -Component 'TelemetryTasks' -Instruction "Deshabilitar $($snapshot.TaskPath)$($snapshot.TaskName)" -Command $command -Reason $_.Exception.Message -Data @{ TaskPath = $snapshot.TaskPath; TaskName = $snapshot.TaskName }
        }
    }
    return $failureCount
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
        'CleanTemporaryFiles' { return (Clear-DebloatTemporaryFiles -Context $Context) }
        'DisableHibernation' { Disable-DebloatHibernation -Context $Context }
        'DisableReservedStorage' { Disable-DebloatReservedStorage -Context $Context }
        'RemoveOneDrive' { Remove-DebloatOneDrive -Context $Context }
        'DisableRecall' { Disable-DebloatRecall -Context $Context }
        'DisableTelemetryTasks' { return (Disable-DebloatTelemetryTasks -Context $Context) }
        default { throw [System.InvalidOperationException]::new("Handler especial no admitido: $($Action.Handler)") }
    }
    return 0
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
                $wasEnabled = if ($record.Value -is [pscustomobject] -and 'WasEnabled' -in $record.Value.PSObject.Properties.Name) {
                    [bool]$record.Value.WasEnabled
                }
                else {
                    [int]$record.Value -ne 0
                }
                $state = if ($wasEnabled) { 'on' } else { 'off' }
                Invoke-DebloatNativeCommand -FilePath 'powercfg.exe' -Arguments "/hibernate $state" -TimeoutSeconds 30 -AllowedExitCodes @(0) | Out-Null
            }
            # Preserve rollback support for backups made before removal of the tweak.
            'ClassicContextMenu' {
                $classPath = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}'
                $path = Join-Path $classPath 'InprocServer32'
                if (-not [bool]$record.Value.KeyExisted) {
                    if (Test-Path -LiteralPath $path) {
                        Remove-Item -LiteralPath $path -Recurse -Force
                    }
                    if (-not [bool]$record.Value.ClassKeyExisted -and (Test-Path -LiteralPath $classPath)) {
                        $classKey = Get-Item -LiteralPath $classPath
                        try {
                            $classKeyIsEmpty = $classKey.SubKeyCount -eq 0 -and $classKey.ValueCount -eq 0
                        }
                        finally {
                            $classKey.Dispose()
                        }
                        if ($classKeyIsEmpty) {
                            Remove-Item -LiteralPath $classPath -Force
                        }
                    }
                }
                else {
                    if (-not (Test-Path -LiteralPath $path)) {
                        New-Item -Path $path -Force | Out-Null
                    }
                    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($path.Substring(6), $true)
                    try {
                        if ([bool]$record.Value.DefaultExisted) {
                            $kind = [Microsoft.Win32.RegistryValueKind]::$($record.Value.DefaultType)
                            $value = switch ([string]$record.Value.DefaultType) {
                                'Binary' { ,([byte[]]@($record.Value.DefaultValue)) }
                                'DWord' { [int]$record.Value.DefaultValue }
                                'QWord' { [long]$record.Value.DefaultValue }
                                'MultiString' { ,([string[]]@($record.Value.DefaultValue)) }
                                default { [string]$record.Value.DefaultValue }
                            }
                            $key.SetValue('', $value, $kind)
                        }
                        else {
                            $key.DeleteValue('', $false)
                        }
                    }
                    finally {
                        $key.Dispose()
                    }
                }
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
                        $taskPathLiteral = ConvertTo-DebloatPowerShellLiteral -Value $taskState.TaskPath
                        $taskNameLiteral = ConvertTo-DebloatPowerShellLiteral -Value $taskState.TaskName
                        Write-DebloatNotApplied -Context $Context -Level Warning -Component 'SpecialRestore' -Instruction "Restaurar la tarea $($taskState.TaskPath)$($taskState.TaskName)" -Command "Get-ScheduledTask -TaskPath $taskPathLiteral -TaskName $taskNameLiteral | Enable-ScheduledTask" -Reason 'La tarea de telemetria respaldada ya no existe.' -Data @{ TaskPath = $taskState.TaskPath; TaskName = $taskState.TaskName }
                        continue
                    }
                    if ($taskState.State -ne 'Disabled' -and -not $task[0].Settings.Enabled) {
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
