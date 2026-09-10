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
        Write-DebloatLog -Context $Context -Level Warning -Component 'Packages' -Message 'No se pudieron consultar los paquetes Appx instalados; se continuara con los provisionados.' -Data @{ ActionId = $ActionId; Pattern = $Pattern; Error = $_.Exception.Message }
    }
    try {
        $provisioned = @(Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like $Pattern -or $_.PackageName -like $Pattern })
    }
    catch {
        $failureCount++
        Write-DebloatLog -Context $Context -Level Warning -Component 'Packages' -Message 'No se pudieron consultar los paquetes provisionados; se continuara con los instalados.' -Data @{ ActionId = $ActionId; Pattern = $Pattern; Error = $_.Exception.Message }
    }
    if ($installed.Count -eq 0 -and $provisioned.Count -eq 0) {
        if ($failureCount -eq 0) {
            Write-DebloatLog -Context $Context -Level Info -Component 'Packages' -Message 'Paquete no instalado; no requiere cambios.' -Data @{ ActionId = $ActionId; Pattern = $Pattern }
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
            Write-DebloatLog -Context $Context -Level Warning -Component 'Packages' -Message 'Se omitio un paquete provisionado y la optimizacion continuara.' -Data @{ ActionId = $ActionId; DisplayName = $package.DisplayName; PackageName = $package.PackageName; Pattern = $Pattern; Error = $_.Exception.Message }
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
            Write-DebloatLog -Context $Context -Level Warning -Component 'Packages' -Message 'Se omitio un paquete Appx y la optimizacion continuara.' -Data @{ ActionId = $ActionId; Name = $package.Name; PackageFullName = $package.PackageFullName; Pattern = $Pattern; Error = $_.Exception.Message }
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
            Write-DebloatLog -Context $Context -Level Warning -Component 'Packages' -Message 'No se pudo procesar un patron y la optimizacion continuara.' -Data @{ ActionId = $Action.Id; Pattern = $pattern; Error = $_.Exception.Message }
        }
    }
    $level = if ($failureCount -gt 0) { 'Warning' } else { 'Success' }
    Write-DebloatLog -Context $Context -Level $level -Component 'PackageAction' -Message 'Grupo de aplicaciones procesado.' -Data @{ ActionId = $Action.Id; Title = $Action.Title; Warnings = $failureCount }
    return $failureCount
}

Export-ModuleMember -Function Invoke-DebloatPackageAction
