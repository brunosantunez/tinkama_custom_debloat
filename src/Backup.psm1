Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Common.psm1')

function New-DebloatSession {
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$ActionIds,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$ServiceIds
    )

    $dataRoot = Get-DebloatDataRoot
    $backupRoot = Join-Path $dataRoot 'Backups'
    if (-not (Test-Path -LiteralPath $backupRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    }

    $sessionName = '{0}_{1}' -f (Get-Date -Format 'yyyyMMdd_HHmmss'), ([Guid]::NewGuid().ToString('N').Substring(0, 8))
    $sessionPath = Join-Path $backupRoot $sessionName
    New-Item -ItemType Directory -Path $sessionPath -Force | Out-Null

    $context = New-DebloatContext -SessionPath $sessionPath
    $metadata = [ordered]@{
        Version = 1
        Status = 'InProgress'
        StartedUtc = [DateTime]::UtcNow.ToString('o')
        CompletedUtc = $null
        ProjectRoot = $ProjectRoot
        ComputerName = $env:COMPUTERNAME
        UserName = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        ActionIds = [string[]]$ActionIds
        ServiceIds = [string[]]$ServiceIds
        ErrorMessage = $null
    }
    Save-DebloatJson -InputObject $metadata -Path (Join-Path $sessionPath 'session.json')
    Write-DebloatLog -Context $context -Level Info -Component 'Session' -Message 'Sesion de respaldo creada.' -Data @{ SessionPath = $sessionPath }
    return $context
}

function Complete-DebloatSession {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context,

        [Parameter(Mandatory)]
        [ValidateSet('Completed', 'CompletedWithWarnings', 'Failed', 'Restored')]
        [string]$Status,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$ErrorMessage
    )

    $metadataPath = Join-Path $Context.SessionPath 'session.json'
    $metadata = Read-DebloatJson -Path $metadataPath
    $metadata.Status = $Status
    $metadata.CompletedUtc = [DateTime]::UtcNow.ToString('o')
    $metadata.ErrorMessage = $ErrorMessage
    Save-DebloatJson -InputObject $metadata -Path $metadataPath
}

function New-DebloatRestorePoint {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Description
    )

    $systemDrive = "$env:SystemDrive\"
    $policyPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $policyName = 'SystemRestorePointCreationFrequency'
    $policyExisted = $false
    $policyValue = $null

    if (Test-Path -LiteralPath $policyPath) {
        $policyKey = Get-Item -LiteralPath $policyPath
        if ($policyName -in $policyKey.GetValueNames()) {
            $policyExisted = $true
            $policyValue = $policyKey.GetValue($policyName)
        }
    }

    try {
        if (-not (Test-Path -LiteralPath $policyPath)) {
            New-Item -Path $policyPath -Force | Out-Null
        }
        New-ItemProperty -LiteralPath $policyPath -Name $policyName -PropertyType DWord -Value 0 -Force | Out-Null
        $driveLiteral = ConvertTo-DebloatPowerShellLiteral -Value $systemDrive
        $descriptionLiteral = ConvertTo-DebloatPowerShellLiteral -Value $Description
        $checkpointScript = "`$ErrorActionPreference = 'Stop'; Enable-ComputerRestore -Drive $driveLiteral; Checkpoint-Computer -Description $descriptionLiteral -RestorePointType MODIFY_SETTINGS"
        $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($checkpointScript))
        $powershellPath = Join-Path $PSHOME 'powershell.exe'
        Invoke-DebloatNativeCommand -FilePath $powershellPath -Arguments "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encodedCommand" -TimeoutSeconds 120 -AllowedExitCodes @(0) | Out-Null
        Write-DebloatLog -Context $Context -Level Success -Component 'RestorePoint' -Message 'Punto de restauracion creado.' -Data @{ Description = $Description; Drive = $systemDrive }
    }
    catch {
        $descriptionLiteral = ConvertTo-DebloatPowerShellLiteral -Value $Description
        $command = "Enable-ComputerRestore -Drive '$systemDrive'; Checkpoint-Computer -Description $descriptionLiteral -RestorePointType MODIFY_SETTINGS"
        $reason = if ($_.Exception -is [System.TimeoutException]) {
            'La creacion del punto de restauracion excedio el limite de 120 segundos y fue cancelada.'
        }
        else {
            $_.Exception.Message
        }
        Write-DebloatNotApplied -Context $Context -Level Error -Component 'RestorePoint' -Instruction "Crear el punto de restauracion obligatorio $Description" -Command $command -Reason $reason -Data @{ Description = $Description; Drive = $systemDrive; TimeoutSeconds = 120 }
        throw [System.InvalidOperationException]::new("No se pudo crear el punto de restauracion obligatorio '$Description'. $reason", $_.Exception)
    }
    finally {
        if ($policyExisted) {
            New-ItemProperty -LiteralPath $policyPath -Name $policyName -PropertyType DWord -Value $policyValue -Force | Out-Null
        }
        elseif (Test-Path -LiteralPath $policyPath) {
            Remove-ItemProperty -LiteralPath $policyPath -Name $policyName -Force
        }
    }
}

function Export-DebloatAppxInventory {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    try {
        $installed = @(Get-AppxPackage -AllUsers | Select-Object Name, PackageFullName, PackageFamilyName, Publisher, InstallLocation)
    }
    catch {
        Write-DebloatNotApplied -Context $Context -Level Error -Component 'Backup' -Instruction 'Guardar el inventario de paquetes Appx instalados' -Command 'Get-AppxPackage -AllUsers' -Reason $_.Exception.Message -Data @{}
        throw
    }
    try {
        $provisioned = @(Get-AppxProvisionedPackage -Online | Select-Object DisplayName, PackageName, PublisherId, InstallLocation)
    }
    catch {
        Write-DebloatNotApplied -Context $Context -Level Error -Component 'Backup' -Instruction 'Guardar el inventario de paquetes provisionados' -Command 'Get-AppxProvisionedPackage -Online' -Reason $_.Exception.Message -Data @{}
        throw
    }
    $inventory = [ordered]@{
        CapturedUtc = [DateTime]::UtcNow.ToString('o')
        Installed = $installed
        Provisioned = $provisioned
    }
    Save-DebloatJson -InputObject $inventory -Path (Join-Path $Context.SessionPath 'appx-inventory.json')
    Write-DebloatLog -Context $Context -Level Info -Component 'Backup' -Message 'Inventario Appx guardado.' -Data @{ Installed = $installed.Count; Provisioned = $provisioned.Count }
}

function Get-LatestDebloatSessionPath {
    [OutputType([string])]
    param()

    $backupRoot = Join-Path (Get-DebloatDataRoot) 'Backups'
    if (-not (Test-Path -LiteralPath $backupRoot -PathType Container)) {
        throw [System.IO.DirectoryNotFoundException]::new('No existen sesiones de respaldo de Pulpo Custom Debloat.')
    }

    $candidates = foreach ($directory in @(Get-ChildItem -LiteralPath $backupRoot -Directory | Sort-Object LastWriteTime -Descending)) {
        $metadataPath = Join-Path $directory.FullName 'session.json'
        if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
            continue
        }
        $metadata = Read-DebloatJson -Path $metadataPath
        if ($metadata.Status -in @('Completed', 'CompletedWithWarnings', 'Failed')) {
            [pscustomobject]@{ Path = $directory.FullName; LastWriteTime = $directory.LastWriteTime }
        }
    }

    $latest = @($candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
    if ($latest.Count -ne 1) {
        throw [System.IO.DirectoryNotFoundException]::new('No existe una sesion pendiente que pueda restaurarse.')
    }
    return $latest[0].Path
}

Export-ModuleMember -Function New-DebloatSession, Complete-DebloatSession, New-DebloatRestorePoint, Export-DebloatAppxInventory, Get-LatestDebloatSessionPath
