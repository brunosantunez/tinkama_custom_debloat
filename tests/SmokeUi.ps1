[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $projectRoot 'src\Catalog.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\UserInterface.psm1') -Force
$catalog = Import-DebloatCatalog -Path (Join-Path $projectRoot 'config\catalog.json')

$application = [System.Windows.Application]::new()
$application.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown
$timer = [System.Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromSeconds(1)
$timer.Add_Tick(({
    $mainWindow = @($application.Windows | Where-Object Title -eq 'Pulpo Custom Debloat' | Select-Object -First 1)
    if ($mainWindow.Count -ne 1) {
        return
    }
    $buttonNames = @('WorkshopProfileButton', 'AggressiveProfileButton', 'ClearSelectionButton', 'SafeProfileButton')
    foreach ($buttonName in $buttonNames) {
        $button = $mainWindow[0].FindName($buttonName)
        $button.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
    }
    $mainWindow[0].UpdateLayout()
    $artifactRoot = Join-Path $projectRoot 'artifacts'
    New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
    $imagePath = Join-Path $artifactRoot 'ui-smoke.png'
    $visualRoot = $mainWindow[0].Content
    $bitmap = [System.Windows.Media.Imaging.RenderTargetBitmap]::new(
        [int]$visualRoot.ActualWidth,
        [int]$visualRoot.ActualHeight,
        96,
        96,
        [System.Windows.Media.PixelFormats]::Pbgra32
    )
    $bitmap.Render($visualRoot)
    $encoder = [System.Windows.Media.Imaging.PngBitmapEncoder]::new()
    $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [System.IO.File]::Create($imagePath)
    try {
        $encoder.Save($stream)
    }
    finally {
        $stream.Dispose()
    }
    $timer.Stop()
    $mainWindow[0].Close()
}).GetNewClosure())
$timer.Start()

Show-DebloatWindow -ProjectRoot $projectRoot -Catalog $catalog
$application.Shutdown()
Write-Output 'WPF smoke test completed without applying actions.'
