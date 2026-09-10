[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $projectRoot 'src\Catalog.psm1')
Import-Module (Join-Path $projectRoot 'src\UserInterface.psm1')
$catalog = Import-DebloatCatalog -Path (Join-Path $projectRoot 'config\catalog.json')
$artifactRoot = Join-Path $projectRoot 'artifacts'
New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null

function Save-WindowScreenshot {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window,
        [Parameter(Mandatory)]
        [string]$Path
    )
    $Window.UpdateLayout()
    $visual = $Window.Content
    $bitmap = [System.Windows.Media.Imaging.RenderTargetBitmap]::new(
        [int]$visual.ActualWidth, [int]$visual.ActualHeight, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32
    )
    $bitmap.Render($visual)
    $encoder = [System.Windows.Media.Imaging.PngBitmapEncoder]::new()
    $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [System.IO.File]::Create($Path)
    try { $encoder.Save($stream) }
    finally { $stream.Dispose() }
}

$application = [System.Windows.Application]::new()
$application.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown
$timer = [System.Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromMilliseconds(500)
$testState = @{ Phase = 'Open'; Failure = $null; Deadline = [DateTime]::UtcNow.AddSeconds(90); LiveLogObserved = $false; DebugReportObserved = $false }
$timer.Add_Tick(({
    $windows = @($application.Windows | Where-Object Name -eq 'MainWindow')
    if ($windows.Count -ne 1) { return }
    $window = $windows[0]
    try {
        if ([DateTime]::UtcNow -gt $testState.Deadline) {
            throw [TimeoutException]::new("La prueba de interfaz excedio 90 segundos. Fase: $($testState.Phase)")
        }
        if ($window.Tag.Busy) {
            if ($testState.Phase -eq 'ProgressSuccess' -and $window.FindName('LogTextBox').Text -match 'Live fixture step.*Current=') {
                $testState.LiveLogObserved = $true
            }
            if ($testState.Phase -eq 'ProgressSuccess' -and $window.FindName('DebugTextBox').Text -match 'Instruccion: Ejecutar incidencia de interfaz simulada') {
                $testState.DebugReportObserved = $true
            }
            return
        }
        if (-not $window.FindName('ApplyButton').IsEnabled) {
            throw [InvalidOperationException]::new('El boton Aplicar no se recupero al finalizar el worker.')
        }
        $outputBase = Join-Path $artifactRoot ([Guid]::NewGuid().ToString('N'))
        switch ($testState.Phase) {
            'Open' {
                foreach ($name in @('WorkshopProfileButton', 'AggressiveProfileButton', 'ClearSelectionButton', 'SafeProfileButton')) {
                    $window.FindName($name).RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
                }
                Save-WindowScreenshot -Window $window -Path (Join-Path $artifactRoot 'ui-smoke.png')
                $window.Width = 920
                $window.Height = 650
                Save-WindowScreenshot -Window $window -Path (Join-Path $artifactRoot 'ui-smoke-compact.png')
                $window.FindName('MainTabs').SelectedIndex = 3
                Save-WindowScreenshot -Window $window -Path (Join-Path $artifactRoot 'ui-tools.png')
                $window.FindName('MainTabs').SelectedIndex = 0
                $job = Start-DebloatWorkerProcess -ScriptPath (Join-Path $projectRoot 'Invoke-Headless.ps1') -ScriptArguments @('-RequestPath', ('"{0}"' -f $outputBase)) -OutputBasePath $outputBase -WorkingDirectory $projectRoot
                $testState.Phase = 'RequestFailure'
            }
            'RequestFailure' {
                if ($null -eq $window.Tag.LastResult -or $window.Tag.LastResult.Success -or [string]::IsNullOrWhiteSpace($window.Tag.LastError)) {
                    throw [InvalidOperationException]::new('La interfaz no mostro el error de solicitud del worker.')
                }
                $job = Start-DebloatWorkerProcess -ScriptPath (Join-Path $projectRoot 'Invoke-Headless.ps1') -ScriptArguments @('-RequestPath', '""') -OutputBasePath $outputBase -WorkingDirectory $projectRoot
                $testState.Phase = 'BootstrapFailure'
            }
            'BootstrapFailure' {
                if ($null -ne $window.Tag.LastResult -or [string]::IsNullOrWhiteSpace($window.Tag.LastError)) {
                    throw [InvalidOperationException]::new('La interfaz no mostro el fallo anterior a generar resultado.')
                }
                Save-WindowScreenshot -Window $window -Path (Join-Path $artifactRoot 'ui-worker-error.png')
                $job = Start-DebloatWorkerProcess -ScriptPath (Join-Path $PSScriptRoot 'Write-ProgressFixture.ps1') -ScriptArguments @('-OutputBasePath', ('"{0}"' -f $outputBase), '-Iterations', '1000') -OutputBasePath $outputBase -WorkingDirectory $projectRoot
                $testState.Phase = 'ProgressSuccess'
            }
            'ProgressSuccess' {
                if ($null -eq $window.Tag.LastResult -or -not $window.Tag.LastResult.Success -or $window.Tag.LastError) {
                    throw [InvalidOperationException]::new("La interfaz no completo el seguimiento de progreso: $($window.Tag.LastError)")
                }
                if (-not $testState.LiveLogObserved) {
                    throw [InvalidOperationException]::new('La interfaz no mostro el registro mientras el worker estaba activo.')
                }
                if (-not $testState.DebugReportObserved -or $window.FindName('DebugTextBox').Text -notmatch 'Comando: Write-ProgressFixture.ps1') {
                    throw [InvalidOperationException]::new('La interfaz no mostro el informe de depuracion estructurado.')
                }
                $window.FindName('MainTabs').SelectedIndex = 5
                Save-WindowScreenshot -Window $window -Path (Join-Path $artifactRoot 'ui-debug.png')
                $timer.Stop()
                $window.Close()
                return
            }
        }
        $testState.Job = $job
        Start-DebloatWorkerMonitor -Job $job -Window $window -Buttons @($window.FindName('ApplyButton'))
    }
    catch {
        $testState.Failure = $_
        $timer.Stop()
        if ($window.Tag.Busy -and $testState.ContainsKey('Job') -and -not $testState.Job.Process.HasExited) {
            $testState.Job.Process.Kill()
            $testState.Job.Process.WaitForExit()
        }
        $window.Tag.Busy = $false
        $window.Close()
    }
}).GetNewClosure())
$timer.Start()

Show-DebloatWindow -ProjectRoot $projectRoot -Catalog $catalog
$application.Shutdown()
if ($null -ne $testState.Failure) { throw $testState.Failure }
Write-Output 'WPF profiles, worker recovery, live progress and live logs passed without system changes.'
