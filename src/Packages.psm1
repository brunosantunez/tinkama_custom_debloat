Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force

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
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context,

        [Parameter(Mandatory)]
        [string]$ActionId,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9.*_-]+$')]
        [string]$Pattern
    )

    $installed = @(Get-AppxPackage -AllUsers | Where-Object Name -Like $Pattern)
    $provisioned = @(Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like $Pattern -or $_.PackageName -like $Pattern })
    if ($installed.Count -eq 0 -and $provisioned.Count -eq 0) {
        Write-DebloatLog -Context $Context -Level Info -Component 'Packages' -Message 'No se encontro el paquete solicitado.' -Data @{ ActionId = $ActionId; Pattern = $Pattern }
        return
    }

    $failures = [System.Collections.Generic.List[string]]::new()
    foreach ($package in @($installed | Sort-Object PackageFullName -Unique)) {
        try {
            Assert-PackageIsRemovable -Name $package.Name
            Remove-AppxPackage -Package $package.PackageFullName -AllUsers
            Write-DebloatLog -Context $Context -Level Success -Component 'Packages' -Message 'Paquete Appx eliminado.' -Data @{ ActionId = $ActionId; Name = $package.Name; PackageFullName = $package.PackageFullName }
        }
        catch {
            $failures.Add("$($package.Name): $($_.Exception.Message)")
            Write-DebloatLog -Context $Context -Level Error -Component 'Packages' -Message 'Fallo la eliminacion de un paquete Appx.' -Data @{ ActionId = $ActionId; Name = $package.Name; Error = $_.Exception.Message }
        }
    }

    foreach ($package in @($provisioned | Sort-Object PackageName -Unique)) {
        try {
            Assert-PackageIsRemovable -Name $package.DisplayName
            Remove-AppxProvisionedPackage -Online -AllUsers -PackageName $package.PackageName | Out-Null
            Write-DebloatLog -Context $Context -Level Success -Component 'Packages' -Message 'Paquete provisionado eliminado.' -Data @{ ActionId = $ActionId; DisplayName = $package.DisplayName; PackageName = $package.PackageName }
        }
        catch {
            $failures.Add("$($package.DisplayName): $($_.Exception.Message)")
            Write-DebloatLog -Context $Context -Level Error -Component 'Packages' -Message 'Fallo la eliminacion de un paquete provisionado.' -Data @{ ActionId = $ActionId; DisplayName = $package.DisplayName; Error = $_.Exception.Message }
        }
    }

    if ($failures.Count -gt 0) {
        throw [System.InvalidOperationException]::new("No se pudieron eliminar todos los paquetes para '$Pattern': $($failures -join ' | ')")
    }
}

function Invoke-DebloatPackageAction {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context,

        [Parameter(Mandatory)]
        [pscustomobject]$Action
    )

    foreach ($pattern in @($Action.PackagePatterns)) {
        Remove-DebloatPackagePattern -Context $Context -ActionId $Action.Id -Pattern $pattern
    }
    Write-DebloatLog -Context $Context -Level Success -Component 'PackageAction' -Message 'Grupo de aplicaciones procesado.' -Data @{ ActionId = $Action.Id; Title = $Action.Title }
}

Export-ModuleMember -Function Invoke-DebloatPackageAction
