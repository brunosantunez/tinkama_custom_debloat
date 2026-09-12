#Requires -RunAsAdministrator
<#
Applies only privacy/background/diagnostic changes on this computer, verifies
registry, service and task state, then restores the saved settings in finally.
Requires a real restore point. Does not remove packages, clean files or reboot.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $projectRoot 'src\Common.psm1')
Import-Module (Join-Path $projectRoot 'src\Catalog.psm1')
Import-Module (Join-Path $projectRoot 'src\Engine.psm1')
Import-Module (Join-Path $projectRoot 'src\Backup.psm1')
Import-Module (Join-Path $projectRoot 'src\Registry.psm1')
Import-Module (Join-Path $projectRoot 'src\Services.psm1')
Import-Module (Join-Path $projectRoot 'src\SystemTweaks.psm1')
$artifactRoot = Join-Path $projectRoot 'artifacts'
New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
$resultPath = Join-Path $artifactRoot 'privacy-host-result.json'
$state = @{ SessionPath = $null; Failure = $null; Restored = $false; Verified = 0; WarningCount = 0 }
try {
    $catalog = Import-DebloatCatalog -Path (Join-Path $projectRoot 'config\catalog.json')
    # Limit the broad permissions action to application diagnostics in this host test.
    $permissionAction = $catalog.Actions | Where-Object Id -eq 'privacy_app_permissions'
    $permissionAction.Registry = @($permissionAction.Registry | Where-Object { $_.Name -like 'LetAppsGetDiagnosticInfo*' -or $_.Path -like '*\appDiagnostics' })
    $actionIds = @('privacy_diagnostics', 'privacy_app_permissions', 'privacy_background_apps', 'privacy_telemetry_tasks')
    $serviceIds = @('svc_diagtrack', 'svc_diagnostics', 'svc_dps', 'svc_wdi_host', 'svc_wdi_system', 'svc_diagsvc', 'svc_wer', 'svc_wer_support', 'svc_performance_logs', 'svc_pca', 'svc_data_usage')
    $callback = {
        param($Message, $Current, $Total, $SessionPath)
        $state.SessionPath = $SessionPath
        Save-DebloatJson -InputObject ([pscustomobject]@{ Message = $Message; Current = $Current; Total = $Total; SessionPath = $SessionPath }) -Path (Join-Path $artifactRoot 'privacy-host-progress.json')
    }.GetNewClosure()
    $result = Invoke-DebloatSelection -ProjectRoot $projectRoot -Catalog $catalog -ActionIds $actionIds -ServiceIds $serviceIds -ProgressCallback $callback
    $state.WarningCount = $result.WarningCount
    foreach ($operation in @($catalog.Actions | Where-Object { $_.Id -in $actionIds -and $_.Kind -eq 'Registry' } | ForEach-Object { $_.Registry })) {
        $key = Get-Item -LiteralPath $operation.Path
        try {
            $value = $key.GetValue($operation.Name)
            if ($key.GetValueKind($operation.Name).ToString() -ne $operation.Type -or
                (@($value) -join '|') -cne (@($operation.Value) -join '|')) {
                throw [System.IO.InvalidDataException]::new("Verificacion fallida: $($operation.Path)\$($operation.Name)")
            }
        }
        finally { $key.Dispose() }
        $state.Verified++
    }
    foreach ($entry in @($catalog.Services | Where-Object Id -in $serviceIds)) {
        $service = Get-CimInstance Win32_Service -Filter "Name='$($entry.Pattern)'"
        if ($null -ne $service) {
            if ($service.StartMode -ne 'Disabled' -or $service.State -ne 'Stopped') {
                throw [System.InvalidOperationException]::new("Servicio no desactivado: $($service.Name), $($service.StartMode), $($service.State)")
            }
            $state.Verified++
        }
    }
    $context = New-DebloatContext -SessionPath $state.SessionPath
    $special = @(Read-DebloatJson -Path (Join-Path $state.SessionPath 'special.json'))
    foreach ($snapshot in @($special | Where-Object Name -eq 'TelemetryTasks' | ForEach-Object { $_.Value })) {
        $task = Get-ScheduledTask -TaskPath $snapshot.TaskPath -TaskName $snapshot.TaskName
        if ($task.Settings.Enabled) {
            throw [System.InvalidOperationException]::new("Tarea no desactivada: $($snapshot.TaskPath)$($snapshot.TaskName). Revisar debug-report.txt.")
        }
        $state.Verified++
    }
}
catch {
    $state.Failure = $_.ToString()
}
finally {
    if ($state.SessionPath) {
        $context = New-DebloatContext -SessionPath $state.SessionPath
        try {
            Restore-DebloatRegistry -Context $context
            Restore-DebloatServices -Context $context
            Restore-DebloatSpecialState -Context $context
            Complete-DebloatSession -Context $context -Status Restored -ErrorMessage ''
            $state.Restored = $true
        }
        catch {
            $state.Failure = "$($state.Failure) Restauracion: $($_.ToString())"
        }
        $null = Save-DebloatDebugReport -SessionPath $state.SessionPath
    }
    Save-DebloatJson -InputObject $state -Path $resultPath
}
if ($state.Failure) { throw [System.InvalidOperationException]::new($state.Failure) }
$state | ConvertTo-Json
