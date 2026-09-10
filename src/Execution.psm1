Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Get-DebloatPowerShellPath {
    [OutputType([string])]
    param()

    $systemFolder = if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        'Sysnative'
    }
    else {
        'System32'
    }
    $path = Join-Path $env:WINDIR "$systemFolder\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw [System.IO.FileNotFoundException]::new("No se encontro Windows PowerShell: $path")
    }
    return $path
}

function Enable-DebloatSessionScripts {
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
        throw [System.Security.SecurityException]::new('PowerShell esta restringido por una politica de control de aplicaciones. Solicita autorizacion al administrador; no se modificara esa politica.')
    }
    foreach ($scope in @('MachinePolicy', 'UserPolicy')) {
        $policy = Get-ExecutionPolicy -Scope $scope
        if ($policy -notin @('Undefined', 'Bypass', 'Unrestricted')) {
            throw [System.Security.SecurityException]::new("La politica $scope exige $policy. Usa una version firmada o solicita autorizacion al administrador. No se alteraran directivas de grupo.")
        }
    }
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
    $sourcePaths = @($ProjectRoot, (Join-Path $ProjectRoot 'src'))
    foreach ($sourcePath in $sourcePaths) {
        foreach ($file in @(Get-ChildItem -LiteralPath $sourcePath -File | Where-Object Extension -in @('.ps1', '.psm1'))) {
            Unblock-File -LiteralPath $file.FullName
        }
    }
    return 'Scripts preparados para esta sesion. UAC y las politicas permanentes no se modificaron.'
}

function Show-DebloatScriptConsent {
    [OutputType([bool])]
    param()

    Add-Type -AssemblyName PresentationFramework
    $window = [System.Windows.Window]::new()
    $window.Name = 'ScriptExecutionConsent'
    $window.Title = 'Pulpo Custom Debloat'
    $window.Width = 570
    $window.Height = 300
    $window.ResizeMode = [System.Windows.ResizeMode]::NoResize
    $window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
    $window.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#111111')
    $window.Foreground = [System.Windows.Media.Brushes]::White
    $window.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')

    $panel = [System.Windows.Controls.StackPanel]::new()
    $panel.Margin = [System.Windows.Thickness]::new(24)
    $title = [System.Windows.Controls.TextBlock]::new()
    $title.Text = 'Permitir ejecucion de scripts'
    $title.FontSize = 20
    $title.FontWeight = [System.Windows.FontWeights]::SemiBold
    $panel.Children.Add($title) | Out-Null

    $message = [System.Windows.Controls.TextBlock]::new()
    $message.Text = 'Pulpo Custom Debloat preparara PowerShell solo para esta sesion y quitara el bloqueo de descarga a sus propios archivos. UAC y Microsoft Defender permaneceran activos.'
    $message.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $message.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#C9C9C9')
    $message.FontSize = 14
    $message.Margin = [System.Windows.Thickness]::new(0, 12, 0, 0)
    $panel.Children.Add($message) | Out-Null

    $buttons = [System.Windows.Controls.StackPanel]::new()
    $buttons.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $buttons.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
    $buttons.Margin = [System.Windows.Thickness]::new(0, 22, 0, 0)
    $cancel = [System.Windows.Controls.Button]::new()
    $cancel.Name = 'CancelButton'
    $cancelLabel = [System.Windows.Controls.TextBlock]::new()
    $cancelLabel.Text = 'Cancelar'
    $cancelLabel.Foreground = [System.Windows.Media.Brushes]::White
    $cancel.Content = $cancelLabel
    $cancel.Width = 110
    $cancel.Height = 38
    $cancel.Margin = [System.Windows.Thickness]::new(0, 0, 10, 0)
    $cancel.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#232323')
    $cancel.Foreground = [System.Windows.Media.Brushes]::White
    $cancel.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#4A4A4A')
    $cancel.IsCancel = $true
    $allow = [System.Windows.Controls.Button]::new()
    $allow.Name = 'AllowButton'
    $allowLabel = [System.Windows.Controls.TextBlock]::new()
    $allowLabel.Text = 'Permitir'
    $allowLabel.Foreground = [System.Windows.Media.Brushes]::White
    $allow.Content = $allowLabel
    $allow.Width = 110
    $allow.Height = 38
    $allow.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#087E5B')
    $allow.Foreground = [System.Windows.Media.Brushes]::White
    $allow.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#087E5B')
    $allow.IsDefault = $true
    $allow.Add_Click({ $window.DialogResult = $true }.GetNewClosure())
    $buttons.Children.Add($cancel) | Out-Null
    $buttons.Children.Add($allow) | Out-Null
    $panel.Children.Add($buttons) | Out-Null
    $window.Content = $panel
    return $window.ShowDialog() -eq $true
}

Export-ModuleMember -Function Get-DebloatPowerShellPath, Enable-DebloatSessionScripts, Show-DebloatScriptConsent
