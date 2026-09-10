Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Common.psm1')

function Get-ProtectedPackageNames {
    [OutputType([string[]])]
    param()

    return @(
        'Microsoft.AAD.BrokerPlugin',
        'Microsoft.AccountsControl',
        'Microsoft.DesktopAppInstaller',
        'Microsoft.LockApp',
        'Microsoft.SecHealthUI',
        'Microsoft.ShellExperienceHost',
        'Microsoft.StorePurchaseApp',
        'Microsoft.Windows.CloudExperienceHost',
        'Microsoft.Windows.StartMenuExperienceHost',
        'Microsoft.WindowsStore',
        'Microsoft.Windows.SecHealthUI',
        'MicrosoftWindows.Client.CBS',
        'MicrosoftWindows.Client.Core',
        'MicrosoftWindows.Client.FileExp'
    )
}

function Assert-PackageIsRemovable {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($Name -in (Get-ProtectedPackageNames)) {
        throw [System.UnauthorizedAccessException]::new("El motor rechazo eliminar el paquete protegido $Name.")
    }
    if ($Name -match '^Microsoft\.(NET\.Native|VCLibs|UI\.Xaml|WindowsAppRuntime)') {
        throw [System.UnauthorizedAccessException]::new("El motor rechazo eliminar el runtime compartido $Name.")
    }
}

function Get-DebloatInstalledPackageQueryCommand {
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Pattern
    )

    $literal = ConvertTo-DebloatPowerShellLiteral -Value $Pattern
    return "Get-AppxPackage -AllUsers | Where-Object Name -Like $literal"
}

function Get-DebloatProvisionedPackageQueryCommand {
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Pattern
    )

    $literal = ConvertTo-DebloatPowerShellLiteral -Value $Pattern
    return "Get-AppxProvisionedPackage -Online | Where-Object { `$_.DisplayName -like $literal -or `$_.PackageName -like $literal }"
}

function Get-DebloatPackageRemovalCommand {
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Pattern
    )

    $installedQuery = Get-DebloatInstalledPackageQueryCommand -Pattern $Pattern
    $provisionedQuery = Get-DebloatProvisionedPackageQueryCommand -Pattern $Pattern
    return "$installedQuery | ForEach-Object { Remove-AppxPackage -Package `$_.PackageFullName -AllUsers }; $provisionedQuery | ForEach-Object { Remove-AppxProvisionedPackage -Online -AllUsers -PackageName `$_.PackageName }"
}

function Remove-DebloatPackagePattern {
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context,

        [Parameter(Mandatory)]
        [string]$ActionId,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9.*_-]+$')]
        [string]$Pattern
    )

    $failureCount = 0
    $installed = @()
    $provisioned = @()
    try {
        $installed = @(Get-AppxPackage -AllUsers | Where-Object Name -Like $Pattern)
    }
    catch {
        $failureCount++
        $command = Get-DebloatInstalledPackageQueryCommand -Pattern $Pattern
        Write-DebloatNotApplied -Context $Context -Level Warning -Component 'Packages' -Instruction "Consultar paquetes Appx instalados que coincidan con $Pattern" -Command $command -Reason $_.Exception.Message -Data @{ ActionId = $ActionId; Pattern = $Pattern }
    }
    try {
        $provisioned = @(Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like $Pattern -or $_.PackageName -like $Pattern })
    }
    catch {
        $failureCount++
        $command = Get-DebloatProvisionedPackageQueryCommand -Pattern $Pattern
        Write-DebloatNotApplied -Context $Context -Level Warning -Component 'Packages' -Instruction "Consultar paquetes provisionados que coincidan con $Pattern" -Command $command -Reason $_.Exception.Message -Data @{ ActionId = $ActionId; Pattern = $Pattern }
    }
    if ($installed.Count -eq 0 -and $provisioned.Count -eq 0) {
        if ($failureCount -eq 0) {
            $command = Get-DebloatPackageRemovalCommand -Pattern $Pattern
            Write-DebloatNotApplied -Context $Context -Level Info -Component 'Packages' -Instruction "Eliminar paquetes instalados o provisionados que coincidan con $Pattern" -Command $command -Reason 'No se encontro ningun paquete instalado o provisionado que coincida.' -Data @{ ActionId = $ActionId; Pattern = $Pattern }
        }
        return $failureCount
    }

    foreach ($package in @($provisioned | Sort-Object PackageName -Unique)) {
        try {
            Assert-PackageIsRemovable -Name $package.DisplayName
            Write-DebloatLog -Context $Context -Level Info -Component 'Packages' -Message 'Eliminando paquete provisionado.' -Data @{ ActionId = $ActionId; DisplayName = $package.DisplayName; PackageName = $package.PackageName; Pattern = $Pattern }
            Remove-AppxProvisionedPackage -Online -AllUsers -PackageName $package.PackageName | Out-Null
            Write-DebloatLog -Context $Context -Level Success -Component 'Packages' -Message 'Paquete provisionado eliminado.' -Data @{ ActionId = $ActionId; DisplayName = $package.DisplayName; PackageName = $package.PackageName; Pattern = $Pattern }
        }
        catch {
            $failureCount++
            $packageLiteral = ConvertTo-DebloatPowerShellLiteral -Value $package.PackageName
            Write-DebloatNotApplied -Context $Context -Level Warning -Component 'Packages' -Instruction "Eliminar paquete provisionado $($package.DisplayName)" -Command "Remove-AppxProvisionedPackage -Online -AllUsers -PackageName $packageLiteral" -Reason $_.Exception.Message -Data @{ ActionId = $ActionId; DisplayName = $package.DisplayName; PackageName = $package.PackageName; Pattern = $Pattern }
        }
    }

    foreach ($package in @($installed | Sort-Object PackageFullName -Unique)) {
        try {
            Assert-PackageIsRemovable -Name $package.Name
            Write-DebloatLog -Context $Context -Level Info -Component 'Packages' -Message 'Eliminando paquete Appx.' -Data @{ ActionId = $ActionId; Name = $package.Name; PackageFullName = $package.PackageFullName; Pattern = $Pattern }
            Remove-AppxPackage -Package $package.PackageFullName -AllUsers
            Write-DebloatLog -Context $Context -Level Success -Component 'Packages' -Message 'Paquete Appx eliminado.' -Data @{ ActionId = $ActionId; Name = $package.Name; PackageFullName = $package.PackageFullName; Pattern = $Pattern }
        }
        catch {
            $failureCount++
            $packageLiteral = ConvertTo-DebloatPowerShellLiteral -Value $package.PackageFullName
            Write-DebloatNotApplied -Context $Context -Level Warning -Component 'Packages' -Instruction "Eliminar paquete Appx $($package.Name)" -Command "Remove-AppxPackage -Package $packageLiteral -AllUsers" -Reason $_.Exception.Message -Data @{ ActionId = $ActionId; Name = $package.Name; PackageFullName = $package.PackageFullName; Pattern = $Pattern }
        }
    }

    return $failureCount
}

function Invoke-DebloatPackageAction {
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context,

        [Parameter(Mandatory)]
        [pscustomobject]$Action
    )

    $failureCount = 0
    foreach ($pattern in @($Action.PackagePatterns)) {
        try {
            $failureCount += Remove-DebloatPackagePattern -Context $Context -ActionId $Action.Id -Pattern $pattern
        }
        catch {
            $failureCount++
            $command = "$(Get-DebloatInstalledPackageQueryCommand -Pattern $pattern); $(Get-DebloatProvisionedPackageQueryCommand -Pattern $pattern)"
            Write-DebloatNotApplied -Context $Context -Level Warning -Component 'Packages' -Instruction "Procesar el patron de paquete $pattern" -Command $command -Reason $_.Exception.Message -Data @{ ActionId = $Action.Id; Pattern = $pattern }
        }
    }
    $level = if ($failureCount -gt 0) { 'Warning' } else { 'Success' }
    Write-DebloatLog -Context $Context -Level $level -Component 'PackageAction' -Message 'Grupo de aplicaciones procesado.' -Data @{ ActionId = $Action.Id; Title = $Action.Title; Warnings = $failureCount }
    return $failureCount
}

Export-ModuleMember -Function Get-DebloatInstalledPackageQueryCommand, Get-DebloatProvisionedPackageQueryCommand, Get-DebloatPackageRemovalCommand, Invoke-DebloatPackageAction
