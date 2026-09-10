Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Common.psm1')
Import-Module (Join-Path $PSScriptRoot 'Registry.psm1')

function Get-ProtectedServiceNames {
    [OutputType([string[]])]
    param()

    return @(
        'BITS', 'CryptSvc', 'DcomLaunch', 'DispBrokerDesktopSvc', 'EventLog', 'gpsvc',
        'mpssvc', 'RpcEptMapper', 'RpcSs', 'SamSs', 'SecurityHealthService', 'TrustedInstaller',
        'WinDefend', 'Winmgmt', 'wuauserv'
    )
}

function Get-ServicesByPattern {
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9._*-]+$')]
        [string]$Pattern
    )

    $wqlPattern = $Pattern.Replace('*', '%')
    return @(Get-CimInstance -ClassName Win32_Service -Filter "Name LIKE '$wqlPattern'")
}

function Get-DebloatServiceCommand {
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet('Automatic', 'Manual', 'Disabled')]
        [string]$StartupType
    )

    $nameLiteral = ConvertTo-DebloatPowerShellLiteral -Value $Name
    $command = "Set-Service -Name $nameLiteral -StartupType $StartupType"
    if ($StartupType -eq 'Disabled') {
        $command += "; Stop-Service -Name $nameLiteral -Force"
    }
    return $command
}

function Save-ServiceSnapshot {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context,

        [Parameter(Mandatory)]
        [object]$Service
    )

    $snapshotPath = Join-Path $Context.SessionPath 'services.json'
    $records = @()
    if (Test-Path -LiteralPath $snapshotPath -PathType Leaf) {
        $records = @(Read-DebloatJson -Path $snapshotPath)
    }
    if (@($records | Where-Object Name -eq $Service.Name).Count -gt 0) {
        return
    }

    $records += [pscustomobject]@{
        Name = [string]$Service.Name
        StartMode = [string]$Service.StartMode
        State = [string]$Service.State
    }
    Save-DebloatJson -InputObject ([object[]]$records) -Path $snapshotPath
}

function Invoke-DebloatServiceAction {
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context,

        [Parameter(Mandatory)]
        [pscustomobject]$ServiceEntry
    )

    if ([bool]$ServiceEntry.Protected) {
        $command = Get-DebloatServiceCommand -Name $ServiceEntry.Pattern -StartupType $ServiceEntry.StartupType
        Write-DebloatNotApplied -Context $Context -Level Warning -Component 'Service' -Instruction "Configurar el servicio protegido $($ServiceEntry.Title)" -Command $command -Reason 'El servicio esta protegido por el catalogo.' -Data @{ ServiceId = $ServiceEntry.Id; Pattern = $ServiceEntry.Pattern; StartupType = $ServiceEntry.StartupType }
        return 1
    }

    if ('TemplateName' -in $ServiceEntry.PSObject.Properties.Name) {
        $templatePath = "HKLM:\SYSTEM\CurrentControlSet\Services\$($ServiceEntry.TemplateName)"
        if (-not (Test-Path -LiteralPath $templatePath)) {
            $startValues = @{ Automatic = 2; Manual = 3; Disabled = 4 }
            $command = "reg.exe add `"HKLM\SYSTEM\CurrentControlSet\Services\$($ServiceEntry.TemplateName)`" /v `"Start`" /t REG_DWORD /d $($startValues[$ServiceEntry.StartupType]) /f"
            Write-DebloatNotApplied -Context $Context -Level Info -Component 'Service' -Instruction "Configurar la plantilla del servicio por usuario $($ServiceEntry.Title)" -Command $command -Reason 'La plantilla del servicio por usuario no existe en este equipo.' -Data @{ ServiceId = $ServiceEntry.Id; TemplateName = $ServiceEntry.TemplateName; StartupType = $ServiceEntry.StartupType }
            return 0
        }
        $startValues = @{ Automatic = 2; Manual = 3; Disabled = 4 }
        $templateAction = [pscustomobject]@{
            Id = "service_template_$($ServiceEntry.Id)"
            Title = $ServiceEntry.Title
            Registry = [object[]]@(
                [pscustomobject]@{ Path = $templatePath; Name = 'Start'; Type = 'DWord'; Value = $startValues[$ServiceEntry.StartupType] }
            )
        }
        $warningCount = Invoke-DebloatRegistryAction -Context $Context -Action $templateAction
        if ($warningCount -eq 0) {
            Write-DebloatLog -Context $Context -Level Success -Component 'Service' -Message 'Plantilla de servicio por usuario configurada; se aplicara completamente al reiniciar sesion.' -Data @{ ServiceId = $ServiceEntry.Id; TemplateName = $ServiceEntry.TemplateName; StartupType = $ServiceEntry.StartupType }
        }
        return $warningCount
    }

    $matches = @(Get-ServicesByPattern -Pattern $ServiceEntry.Pattern)
    if ($matches.Count -eq 0) {
        $command = Get-DebloatServiceCommand -Name $ServiceEntry.Pattern -StartupType $ServiceEntry.StartupType
        Write-DebloatNotApplied -Context $Context -Level Info -Component 'Service' -Instruction "Configurar el servicio $($ServiceEntry.Title)" -Command $command -Reason 'El servicio opcional no existe en este equipo.' -Data @{ ServiceId = $ServiceEntry.Id; Pattern = $ServiceEntry.Pattern; StartupType = $ServiceEntry.StartupType }
        return 0
    }

    $protected = Get-ProtectedServiceNames
    $failureCount = 0
    foreach ($service in $matches) {
        try {
            if ($service.Name -in $protected) {
                throw [System.UnauthorizedAccessException]::new("El motor rechazo modificar el servicio critico $($service.Name).")
            }

            Save-ServiceSnapshot -Context $Context -Service $service
            Set-Service -Name $service.Name -StartupType $ServiceEntry.StartupType
            if ($ServiceEntry.StartupType -eq 'Disabled' -and $service.State -ne 'Stopped') {
                Stop-Service -Name $service.Name -Force
            }
            Write-DebloatLog -Context $Context -Level Success -Component 'Service' -Message 'Tipo de inicio de servicio aplicado.' -Data @{ ServiceId = $ServiceEntry.Id; Name = $service.Name; Previous = $service.StartMode; StartupType = $ServiceEntry.StartupType }
        }
        catch {
            $failureCount++
            $command = Get-DebloatServiceCommand -Name $service.Name -StartupType $ServiceEntry.StartupType
            Write-DebloatNotApplied -Context $Context -Level Warning -Component 'Service' -Instruction "Configurar el servicio $($service.Name)" -Command $command -Reason $_.Exception.Message -Data @{ ServiceId = $ServiceEntry.Id; Name = $service.Name; StartupType = $ServiceEntry.StartupType }
        }
    }
    return $failureCount
}

function Restore-DebloatServices {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $snapshotPath = Join-Path $Context.SessionPath 'services.json'
    if (-not (Test-Path -LiteralPath $snapshotPath -PathType Leaf)) {
        Write-DebloatLog -Context $Context -Level Info -Component 'ServiceRestore' -Message 'La sesion no contiene servicios para restaurar.' -Data @{}
        return
    }

    $startModeMap = @{
        Auto = 'Automatic'
        Automatic = 'Automatic'
        Manual = 'Manual'
        Disabled = 'Disabled'
    }
    $records = @(Read-DebloatJson -Path $snapshotPath)
    for ($index = $records.Count - 1; $index -ge 0; $index--) {
        $record = $records[$index]
        if (-not $startModeMap.ContainsKey([string]$record.StartMode)) {
            throw [System.InvalidOperationException]::new("No se puede restaurar el modo de inicio '$($record.StartMode)' de $($record.Name).")
        }

        $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$($record.Name)'"
        if ($null -eq $service) {
            $targetMode = $startModeMap[[string]$record.StartMode]
            $command = Get-DebloatServiceCommand -Name $record.Name -StartupType $targetMode
            Write-DebloatNotApplied -Context $Context -Level Warning -Component 'ServiceRestore' -Instruction "Restaurar el servicio $($record.Name)" -Command $command -Reason 'La instancia respaldada ya no existe; los servicios por usuario pueden cambiar de sufijo despues de reiniciar.' -Data @{ Name = $record.Name; StartupType = $targetMode }
            continue
        }

        $targetMode = $startModeMap[[string]$record.StartMode]
        Set-Service -Name $record.Name -StartupType $targetMode
        if ($record.State -eq 'Running' -and $targetMode -ne 'Disabled') {
            Start-Service -Name $record.Name
        }
        Write-DebloatLog -Context $Context -Level Success -Component 'ServiceRestore' -Message 'Servicio restaurado.' -Data @{ Name = $record.Name; StartupType = $targetMode; PreviousState = $record.State }
    }
}

Export-ModuleMember -Function Get-DebloatServiceCommand, Invoke-DebloatServiceAction, Restore-DebloatServices
