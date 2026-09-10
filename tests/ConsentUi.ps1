[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $projectRoot 'src\Execution.psm1')
Add-Type -AssemblyName PresentationFramework
$application = [System.Windows.Application]::new()
$application.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown
$testState = @{ Seen = $false; Failure = $null }
$timer = [System.Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromMilliseconds(200)
$timer.Add_Tick(({
    try {
        $windows = @($application.Windows | Where-Object Name -eq 'ScriptExecutionConsent')
        if ($windows.Count -ne 1) { return }
        $window = $windows[0]
        $buttons = @($window.Content.Children[2].Children | Where-Object Name -in @('CancelButton', 'AllowButton'))
        if ($buttons.Count -ne 2) {
            throw [System.InvalidOperationException]::new('La confirmacion no contiene sus dos botones estables.')
        }
        $testState.Seen = $true
        $window.UpdateLayout()
        $visual = $window.Content
        $bitmap = [System.Windows.Media.Imaging.RenderTargetBitmap]::new(
            [int]$visual.ActualWidth, [int]$visual.ActualHeight, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32
        )
        $bitmap.Render($visual)
        $encoder = [System.Windows.Media.Imaging.PngBitmapEncoder]::new()
        $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $artifactRoot = Join-Path $projectRoot 'artifacts'
        New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
        $stream = [System.IO.File]::Create((Join-Path $artifactRoot 'ui-script-consent.png'))
        try { $encoder.Save($stream) }
        finally { $stream.Dispose() }
        $timer.Stop()
        $window.DialogResult = $true
    }
    catch {
        $testState.Failure = $_
        $timer.Stop()
        if ($application.Windows.Count -gt 0) {
            $application.Windows[0].DialogResult = $false
        }
    }
}).GetNewClosure())
$timer.Start()
$allowed = Show-DebloatScriptConsent
$application.Shutdown()
if ($null -ne $testState.Failure) { throw $testState.Failure }
if (-not $allowed -or -not $testState.Seen) {
    throw [System.InvalidOperationException]::new('La confirmacion no acepto la decision del usuario.')
}
Write-Output 'Script execution consent rendered and accepted without changing policy.'
