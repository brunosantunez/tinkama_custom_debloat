Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Common.psm1')

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
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context,

        [Parameter(Mandatory)]
        [pscustomobject]$ServiceEntry
    )

    if ([bool]$ServiceEntry.Protected) {
        throw [System.UnauthorizedAccessException]::new("El servicio $($ServiceEntry.Pattern) esta protegido por el catalogo.")
    }

    $matches = @(Get-ServicesByPattern -Pattern $ServiceEntry.Pattern)
    if ($matches.Count -eq 0) {
        Write-DebloatLog -Context $Context -Level Info -Component 'Service' -Message 'El servicio opcional no existe en este equipo.' -Data @{ ServiceId = $ServiceEntry.Id; Pattern = $ServiceEntry.Pattern }
        return
    }

    $protected = Get-ProtectedServiceNames
    foreach ($service in $matches) {
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
            Write-DebloatLog -Context $Context -Level Warning -Component 'ServiceRestore' -Message 'La instancia de servicio respaldada ya no existe.' -Data @{ Name = $record.Name; Reason = 'Los servicios por usuario pueden cambiar de sufijo despues de reiniciar.' }
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

Export-ModuleMember -Function Invoke-DebloatServiceAction, Restore-DebloatServices
