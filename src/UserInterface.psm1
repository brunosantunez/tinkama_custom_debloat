Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

function Get-WindowElement {
    [OutputType([System.Windows.DependencyObject])]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $element = $Window.FindName($Name)
    if ($null -eq $element) {
        throw [System.InvalidOperationException]::new("La interfaz no contiene el control requerido: $Name")
    }
    return $element
}

function New-SectionHeader {
    [OutputType([System.Windows.Controls.StackPanel])]
    param(
        [Parameter(Mandatory)]
        [string]$Title
    )

    $container = [System.Windows.Controls.StackPanel]::new()
    $container.Margin = [System.Windows.Thickness]::new(0, 10, 0, 6)

    $titleBlock = [System.Windows.Controls.TextBlock]::new()
    $titleBlock.Text = $Title
    $titleBlock.FontSize = 17
    $titleBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
    $titleBlock.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#171A1D')
    $container.Children.Add($titleBlock) | Out-Null

    $separator = [System.Windows.Controls.Border]::new()
    $separator.Height = 1
    $separator.Margin = [System.Windows.Thickness]::new(0, 8, 0, 0)
    $separator.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#D8DCDF')
    $container.Children.Add($separator) | Out-Null
    return $container
}

function New-OptionCheckBox {
    [OutputType([System.Windows.Controls.CheckBox])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Entry,

        [Parameter(Mandatory)]
        [bool]$Protected
    )

    $riskLabels = @{ Low = 'BAJO'; Medium = 'MEDIO'; High = 'ALTO'; Critical = 'CRITICO' }
    $riskColors = @{ Low = '#087E5B'; Medium = '#8A5A00'; High = '#B85C00'; Critical = '#B42318' }

    $checkBox = [System.Windows.Controls.CheckBox]::new()
    $checkBox.Tag = [string]$Entry.Id
    $checkBox.IsEnabled = -not $Protected
    $checkBox.Margin = [System.Windows.Thickness]::new(2, 7, 0, 8)
    $checkBox.VerticalContentAlignment = [System.Windows.VerticalAlignment]::Top

    $content = [System.Windows.Controls.StackPanel]::new()
    $content.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)

    $titleRow = [System.Windows.Controls.StackPanel]::new()
    $titleRow.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $title = [System.Windows.Controls.TextBlock]::new()
    $title.Text = [string]$Entry.Title
    $title.FontSize = 14
    $title.FontWeight = [System.Windows.FontWeights]::SemiBold
    $title.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#171A1D')
    $titleRow.Children.Add($title) | Out-Null

    $risk = [System.Windows.Controls.TextBlock]::new()
    $risk.Text = if ($Protected) { 'PROTEGIDO' } else { $riskLabels[[string]$Entry.Risk] }
    $risk.FontSize = 10
    $risk.FontWeight = [System.Windows.FontWeights]::Bold
    $risk.Margin = [System.Windows.Thickness]::new(10, 3, 0, 0)
    $riskColor = if ($Protected) { '#626970' } else { $riskColors[[string]$Entry.Risk] }
    $risk.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($riskColor)
    $titleRow.Children.Add($risk) | Out-Null
    $content.Children.Add($titleRow) | Out-Null

    $description = [System.Windows.Controls.TextBlock]::new()
    $description.Text = [string]$Entry.Description
    $description.FontSize = 12
    $description.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#626970')
    $description.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $description.MaxWidth = 820
    $description.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
    $content.Children.Add($description) | Out-Null

    $checkBox.Content = $content
    return $checkBox
}

function Add-ActionSections {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.Panel]$Panel,

        [Parameter(Mandatory)]
        [object[]]$Entries,

        [Parameter(Mandatory)]
        [hashtable]$CheckBoxes
    )

    foreach ($group in @($Entries | Group-Object Category)) {
        $Panel.Children.Add((New-SectionHeader -Title $group.Name)) | Out-Null
        foreach ($entry in @($group.Group)) {
            $checkBox = New-OptionCheckBox -Entry $entry -Protected $false
            $CheckBoxes[[string]$entry.Id] = $checkBox
            $Panel.Children.Add($checkBox) | Out-Null
        }
    }
}

function Add-ServiceSections {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.Panel]$Panel,

        [Parameter(Mandatory)]
        [object[]]$Entries,

        [Parameter(Mandatory)]
        [hashtable]$CheckBoxes
    )

    $riskOrder = @('Low', 'Medium', 'High', 'Critical')
    $riskTitles = @{
        Low = 'Servicios de impacto bajo'
        Medium = 'Servicios opcionales'
        High = 'Servicios con impacto funcional'
        Critical = 'Servicios de alto riesgo y protegidos'
    }

    foreach ($riskName in $riskOrder) {
        $entriesForRisk = @($Entries | Where-Object Risk -eq $riskName)
        if ($entriesForRisk.Count -eq 0) {
            continue
        }
        $Panel.Children.Add((New-SectionHeader -Title $riskTitles[$riskName])) | Out-Null
        foreach ($entry in $entriesForRisk) {
            $checkBox = New-OptionCheckBox -Entry $entry -Protected ([bool]$entry.Protected)
            $CheckBoxes[[string]$entry.Id] = $checkBox
            $Panel.Children.Add($checkBox) | Out-Null
        }
    }
}

function Get-SelectedIds {
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$CheckBoxes
    )

    $selected = [string[]]@(
        $CheckBoxes.GetEnumerator() |
            Where-Object { $_.Value.IsChecked -eq $true } |
            ForEach-Object Key |
            Sort-Object
    )
    Write-Output -NoEnumerate $selected
}

function Set-ProfileSelection {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Catalog,

        [Parameter(Mandatory)]
        [string]$ProfileId,

        [Parameter(Mandatory)]
        [hashtable]$ActionCheckBoxes,

        [Parameter(Mandatory)]
        [hashtable]$ServiceCheckBoxes
    )

    $profiles = @($Catalog.Profiles | Where-Object Id -eq $ProfileId)
    if ($profiles.Count -ne 1) {
        throw [System.IO.InvalidDataException]::new("No existe el perfil: $ProfileId")
    }
    $profile = $profiles[0]
    foreach ($entry in $ActionCheckBoxes.GetEnumerator()) {
        $entry.Value.IsChecked = $entry.Key -in @($profile.ActionIds)
    }
    foreach ($entry in $ServiceCheckBoxes.GetEnumerator()) {
        if ($entry.Value.IsEnabled) {
            $entry.Value.IsChecked = $entry.Key -in @($profile.ServiceIds)
        }
    }
}

function Clear-DebloatSelection {
    param(
        [Parameter(Mandatory)]
        [hashtable]$ActionCheckBoxes,

        [Parameter(Mandatory)]
        [hashtable]$ServiceCheckBoxes
    )

    foreach ($entry in $ActionCheckBoxes.GetEnumerator()) {
        $entry.Value.IsChecked = $false
    }
    foreach ($entry in $ServiceCheckBoxes.GetEnumerator()) {
        if ($entry.Value.IsEnabled) {
            $entry.Value.IsChecked = $false
        }
    }
}

function Update-SelectionSummary {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.TextBlock]$TextBlock,

        [Parameter(Mandatory)]
        [hashtable]$ActionCheckBoxes,

        [Parameter(Mandatory)]
        [hashtable]$ServiceCheckBoxes
    )

    $actionCount = (Get-SelectedIds -CheckBoxes $ActionCheckBoxes).Count
    $serviceCount = (Get-SelectedIds -CheckBoxes $ServiceCheckBoxes).Count
    $TextBlock.Text = "$actionCount ajustes / $serviceCount servicios"
}

function Show-SelectionPreview {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Owner,

        [Parameter(Mandatory)]
        [pscustomobject]$Catalog,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$ActionIds,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$ServiceIds
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("AJUSTES ($($ActionIds.Count))")
    foreach ($entry in @($Catalog.Actions | Where-Object Id -in $ActionIds | Sort-Object Category, Title)) {
        $lines.Add("[$($entry.Risk)] $($entry.Title)")
    }
    $lines.Add('')
    $lines.Add("SERVICIOS ($($ServiceIds.Count))")
    foreach ($entry in @($Catalog.Services | Where-Object Id -in $ServiceIds | Sort-Object Risk, Title)) {
        $lines.Add("[$($entry.Risk)] $($entry.Title) -> $($entry.StartupType)")
    }

    $preview = [System.Windows.Window]::new()
    $preview.Title = 'Previsualizacion'
    $preview.Owner = $Owner
    $preview.Width = 720
    $preview.Height = 560
    $preview.MinWidth = 520
    $preview.MinHeight = 400
    $preview.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner
    $preview.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#F4F5F6')

    $grid = [System.Windows.Controls.Grid]::new()
    $grid.Margin = [System.Windows.Thickness]::new(18)
    $grid.RowDefinitions.Add([System.Windows.Controls.RowDefinition]::new())
    $buttonRow = [System.Windows.Controls.RowDefinition]::new()
    $buttonRow.Height = [System.Windows.GridLength]::Auto
    $grid.RowDefinitions.Add($buttonRow)

    $text = [System.Windows.Controls.TextBox]::new()
    $text.IsReadOnly = $true
    $text.Text = $lines -join [Environment]::NewLine
    $text.FontFamily = [System.Windows.Media.FontFamily]::new('Consolas')
    $text.FontSize = 12
    $text.AcceptsReturn = $true
    $text.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
    $text.HorizontalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
    $text.Padding = [System.Windows.Thickness]::new(10)
    $grid.Children.Add($text) | Out-Null

    $close = [System.Windows.Controls.Button]::new()
    $close.Content = 'Cerrar'
    $close.MinWidth = 100
    $close.Margin = [System.Windows.Thickness]::new(0, 12, 0, 0)
    $close.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
    [System.Windows.Controls.Grid]::SetRow($close, 1)
    $close.Add_Click({ $preview.Close() }.GetNewClosure())
    $grid.Children.Add($close) | Out-Null
    $preview.Content = $grid
    $preview.ShowDialog() | Out-Null
}

function Get-FormattedSessionLog {
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$SessionPath
    )

    $logPath = Join-Path $SessionPath 'operations.jsonl'
    if (-not (Test-Path -LiteralPath $logPath -PathType Leaf)) {
        return 'La sesion no contiene registro de operaciones.'
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($rawLine in @(Get-Content -LiteralPath $logPath | Select-Object -Last 250)) {
        $entry = $rawLine | ConvertFrom-Json
        $time = [DateTime]::Parse($entry.TimestampUtc).ToLocalTime().ToString('HH:mm:ss')
        $lines.Add("$time [$($entry.Level)] [$($entry.Component)] $($entry.Message)")
    }
    return $lines -join [Environment]::NewLine
}

function Set-WindowBusy {
    param(
        [Parameter(Mandatory)]
        [bool]$Busy,

        [Parameter(Mandatory)]
        [System.Windows.Controls.Button[]]$Buttons,

        [Parameter(Mandatory)]
        [System.Windows.Controls.ProgressBar]$ProgressBar
    )

    foreach ($button in $Buttons) {
        $button.IsEnabled = -not $Busy
    }
    $ProgressBar.IsIndeterminate = $Busy
    if (-not $Busy) {
        $ProgressBar.Value = 0
    }
}

function Show-DebloatWindow {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [Parameter(Mandatory)]
        [pscustomobject]$Catalog
    )

    $xamlPath = Join-Path $ProjectRoot 'ui\MainWindow.xaml'
    if (-not (Test-Path -LiteralPath $xamlPath -PathType Leaf)) {
        throw [System.IO.FileNotFoundException]::new("No se encontro la interfaz: $xamlPath")
    }
    [xml]$xaml = Get-Content -LiteralPath $xamlPath -Raw
    $reader = [System.Xml.XmlNodeReader]::new($xaml)
    $window = [Windows.Markup.XamlReader]::Load($reader)

    $settingsPanel = Get-WindowElement -Window $window -Name 'SettingsPanel'
    $appsPanel = Get-WindowElement -Window $window -Name 'AppsPanel'
    $servicesPanel = Get-WindowElement -Window $window -Name 'ServicesPanel'
    $toolsPanel = Get-WindowElement -Window $window -Name 'ToolsPanel'
    $selectionText = Get-WindowElement -Window $window -Name 'SelectionText'
    $statusText = Get-WindowElement -Window $window -Name 'StatusText'
    $progressBar = Get-WindowElement -Window $window -Name 'WorkProgress'
    $logTextBox = Get-WindowElement -Window $window -Name 'LogTextBox'
    $systemInfoText = Get-WindowElement -Window $window -Name 'SystemInfoText'
    $safeButton = Get-WindowElement -Window $window -Name 'SafeProfileButton'
    $workshopButton = Get-WindowElement -Window $window -Name 'WorkshopProfileButton'
    $aggressiveButton = Get-WindowElement -Window $window -Name 'AggressiveProfileButton'
    $clearButton = Get-WindowElement -Window $window -Name 'ClearSelectionButton'
    $previewButton = Get-WindowElement -Window $window -Name 'PreviewButton'
    $applyButton = Get-WindowElement -Window $window -Name 'ApplyButton'
    $restoreButton = Get-WindowElement -Window $window -Name 'RestoreSettingsButton'
    $systemRestoreButton = Get-WindowElement -Window $window -Name 'OpenSystemRestoreButton'
    $openBackupsButton = Get-WindowElement -Window $window -Name 'OpenBackupsButton'

    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $systemInfoText.Text = "$($os.Caption) | Build $($os.BuildNumber) | $env:COMPUTERNAME"

    $actionCheckBoxes = @{}
    $serviceCheckBoxes = @{}
    $applicationActions = @($Catalog.Actions | Where-Object Category -eq 'Aplicaciones' | Sort-Object Title)
    $categoryOrder = @{ Privacidad = 0; Rendimiento = 1; Sistema = 2; Mantenimiento = 3 }
    $settingsActions = @(
        $Catalog.Actions |
            Where-Object Category -ne 'Aplicaciones' |
            Sort-Object @{ Expression = { $categoryOrder[[string]$_.Category] } }, Title
    )
    Add-ActionSections -Panel $settingsPanel -Entries $settingsActions -CheckBoxes $actionCheckBoxes
    Add-ActionSections -Panel $appsPanel -Entries $applicationActions -CheckBoxes $actionCheckBoxes
    Add-ServiceSections -Panel $servicesPanel -Entries @($Catalog.Services) -CheckBoxes $serviceCheckBoxes

    $selectionChanged = {
        Update-SelectionSummary -TextBlock $selectionText -ActionCheckBoxes $actionCheckBoxes -ServiceCheckBoxes $serviceCheckBoxes
    }.GetNewClosure()
    foreach ($checkBox in @($actionCheckBoxes.Values) + @($serviceCheckBoxes.Values)) {
        $checkBox.Add_Checked($selectionChanged)
        $checkBox.Add_Unchecked($selectionChanged)
    }

    foreach ($tool in @($Catalog.Tools | Sort-Object Title)) {
        $button = [System.Windows.Controls.Button]::new()
        $button.Width = 220
        $button.Height = 48
        $button.Margin = [System.Windows.Thickness]::new(0, 0, 10, 10)
        $button.Tag = [string]$tool.Url
        $content = [System.Windows.Controls.StackPanel]::new()
        $content.Orientation = [System.Windows.Controls.Orientation]::Horizontal
        $icon = [System.Windows.Controls.TextBlock]::new()
        $icon.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        $icon.Text = [char]0xE896
        $icon.Margin = [System.Windows.Thickness]::new(0, 0, 9, 0)
        $label = [System.Windows.Controls.TextBlock]::new()
        $label.Text = [string]$tool.Title
        $content.Children.Add($icon) | Out-Null
        $content.Children.Add($label) | Out-Null
        $button.Content = $content
        $button.Add_Click(({ param($sender, $eventArgs) Start-Process -FilePath ([string]$sender.Tag) }.GetNewClosure()))
        $toolsPanel.Children.Add($button) | Out-Null
    }

    $busyButtons = [System.Windows.Controls.Button[]]@(
        $safeButton, $workshopButton, $aggressiveButton, $clearButton,
        $previewButton, $applyButton, $restoreButton, $systemRestoreButton
    )

    $safeButton.Add_Click(({
        Set-ProfileSelection -Catalog $Catalog -ProfileId 'Safe' -ActionCheckBoxes $actionCheckBoxes -ServiceCheckBoxes $serviceCheckBoxes
        $statusText.Text = 'Perfil Basica segura seleccionado'
    }).GetNewClosure())
    $workshopButton.Add_Click(({
        Set-ProfileSelection -Catalog $Catalog -ProfileId 'Workshop' -ActionCheckBoxes $actionCheckBoxes -ServiceCheckBoxes $serviceCheckBoxes
        $statusText.Text = 'Perfil Taller completo seleccionado'
    }).GetNewClosure())
    $aggressiveButton.Add_Click(({
        Set-ProfileSelection -Catalog $Catalog -ProfileId 'Aggressive' -ActionCheckBoxes $actionCheckBoxes -ServiceCheckBoxes $serviceCheckBoxes
        $statusText.Text = 'Perfil Captura agresiva seleccionado'
    }).GetNewClosure())
    $clearButton.Add_Click(({
        Clear-DebloatSelection -ActionCheckBoxes $actionCheckBoxes -ServiceCheckBoxes $serviceCheckBoxes
        $statusText.Text = 'Seleccion vacia'
    }).GetNewClosure())

    $previewButton.Add_Click(({
        $actionIds = Get-SelectedIds -CheckBoxes $actionCheckBoxes
        $serviceIds = Get-SelectedIds -CheckBoxes $serviceCheckBoxes
        Show-SelectionPreview -Owner $window -Catalog $Catalog -ActionIds $actionIds -ServiceIds $serviceIds
    }).GetNewClosure())

    $applyButton.Add_Click(({
        try {
            $actionIds = Get-SelectedIds -CheckBoxes $actionCheckBoxes
            $serviceIds = Get-SelectedIds -CheckBoxes $serviceCheckBoxes
            if ($actionIds.Count + $serviceIds.Count -eq 0) {
                [System.Windows.MessageBox]::Show($window, 'No hay acciones seleccionadas.', 'Pulpo Custom Debloat', 'OK', 'Information') | Out-Null
                return
            }

            $highRiskEntries = @(
                $Catalog.Actions | Where-Object { $_.Id -in $actionIds -and $_.Risk -in @('High', 'Critical') }
            ) + @(
                $Catalog.Services | Where-Object { $_.Id -in $serviceIds -and $_.Risk -in @('High', 'Critical') }
            )
            if ($highRiskEntries.Count -gt 0) {
                $names = @($highRiskEntries | Select-Object -ExpandProperty Title | Select-Object -First 12)
                $suffix = if ($highRiskEntries.Count -gt 12) {
                    [Environment]::NewLine + "... y $($highRiskEntries.Count - 12) acciones mas."
                }
                else {
                    ''
                }
                $separator = [Environment]::NewLine
                $riskMessage = 'Seleccionaste acciones de riesgo alto:' + $separator + $separator +
                    ($names -join $separator) + $suffix + $separator + $separator +
                    'Pueden afectar aplicaciones, impresion, camara, busqueda o juegos. Deseas continuar?'
                $riskResult = [System.Windows.MessageBox]::Show($window, $riskMessage, 'Confirmar acciones de riesgo', 'YesNo', 'Warning')
                if ($riskResult -ne 'Yes') {
                    return
                }
            }

            $confirmation = "Se creara un punto de restauracion obligatorio y luego se aplicaran $($actionIds.Count) ajustes y $($serviceIds.Count) servicios." +
                [Environment]::NewLine + [Environment]::NewLine +
                'Los temporales eliminados no se pueden recuperar. Continuar?'
            $confirmResult = [System.Windows.MessageBox]::Show($window, $confirmation, 'Aplicar seleccion', 'YesNo', 'Question')
            if ($confirmResult -ne 'Yes') {
                return
            }

            $requestsRoot = Join-Path (Get-DebloatDataRoot) 'Requests'
            New-Item -ItemType Directory -Path $requestsRoot -Force | Out-Null
            $requestPath = Join-Path $requestsRoot ("{0}.json" -f [Guid]::NewGuid().ToString('N'))
            Save-DebloatJson -InputObject ([pscustomobject]@{ ActionIds = $actionIds; ServiceIds = $serviceIds }) -Path $requestPath

            $workerScript = Join-Path $ProjectRoot 'Invoke-Headless.ps1'
            $workerArguments = @(
                '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                '-File', ('"{0}"' -f $workerScript),
                '-RequestPath', ('"{0}"' -f $requestPath)
            )
            $worker = Start-Process -FilePath 'powershell.exe' -ArgumentList $workerArguments -WindowStyle Hidden -PassThru -WorkingDirectory $ProjectRoot
            $resultPath = "$requestPath.result.json"
            $progressPath = "$requestPath.progress.json"
            Set-WindowBusy -Busy $true -Buttons $busyButtons -ProgressBar $progressBar
            $statusText.Text = 'Iniciando optimizacion'

            $timer = [System.Windows.Threading.DispatcherTimer]::new()
            $timer.Interval = [TimeSpan]::FromMilliseconds(500)
            $timer.Add_Tick(({
                if (Test-Path -LiteralPath $progressPath -PathType Leaf) {
                    $progress = Read-DebloatJson -Path $progressPath
                    $statusText.Text = [string]$progress.Message
                    if ([int]$progress.Total -gt 0) {
                        $progressBar.IsIndeterminate = $false
                        $progressBar.Value = [Math]::Round(([int]$progress.Current / [int]$progress.Total) * 100)
                    }
                }
                if (-not $worker.HasExited) {
                    return
                }

                $timer.Stop()
                Set-WindowBusy -Busy $false -Buttons $busyButtons -ProgressBar $progressBar
                if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
                    $statusText.Text = "El proceso termino con codigo $($worker.ExitCode) sin generar resultado"
                    [System.Windows.MessageBox]::Show($window, $statusText.Text, 'Error de optimizacion', 'OK', 'Error') | Out-Null
                    return
                }
                $result = Read-DebloatJson -Path $resultPath
                $statusText.Text = [string]$result.Message
                if ($result.SessionPath) {
                    $logTextBox.Text = Get-FormattedSessionLog -SessionPath ([string]$result.SessionPath)
                    $logTextBox.ScrollToEnd()
                }
                $iconName = if ([bool]$result.Success) { 'Information' } else { 'Error' }
                [System.Windows.MessageBox]::Show($window, [string]$result.Message, 'Pulpo Custom Debloat', 'OK', $iconName) | Out-Null
            }).GetNewClosure())
            $timer.Start()
        }
        catch {
            Set-WindowBusy -Busy $false -Buttons $busyButtons -ProgressBar $progressBar
            $statusText.Text = $_.Exception.Message
            [System.Windows.MessageBox]::Show($window, $_.Exception.Message, 'Error de optimizacion', 'OK', 'Error') | Out-Null
        }
    }).GetNewClosure())

    $restoreButton.Add_Click(({
        try {
            $confirmation = 'Se restaurara la ultima sesion disponible. Las aplicaciones eliminadas requieren Restaurar sistema. Continuar?'
            if ([System.Windows.MessageBox]::Show($window, $confirmation, 'Restaurar ajustes', 'YesNo', 'Question') -ne 'Yes') {
                return
            }
            $resultPath = Join-Path (Get-DebloatDataRoot) 'restore-result.json'
            if (Test-Path -LiteralPath $resultPath -PathType Leaf) {
                Remove-Item -LiteralPath $resultPath -Force
            }
            $restoreScript = Join-Path $ProjectRoot 'Restore-LastSession.ps1'
            $arguments = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $restoreScript))
            $worker = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden -PassThru -WorkingDirectory $ProjectRoot
            Set-WindowBusy -Busy $true -Buttons $busyButtons -ProgressBar $progressBar
            $statusText.Text = 'Restaurando ultimo respaldo'

            $timer = [System.Windows.Threading.DispatcherTimer]::new()
            $timer.Interval = [TimeSpan]::FromMilliseconds(500)
            $timer.Add_Tick(({
                if (-not $worker.HasExited) {
                    return
                }
                $timer.Stop()
                Set-WindowBusy -Busy $false -Buttons $busyButtons -ProgressBar $progressBar
                if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
                    $statusText.Text = "La restauracion termino con codigo $($worker.ExitCode) sin generar resultado"
                    [System.Windows.MessageBox]::Show($window, $statusText.Text, 'Error de restauracion', 'OK', 'Error') | Out-Null
                    return
                }
                $result = Read-DebloatJson -Path $resultPath
                $statusText.Text = [string]$result.Message
                if ($result.SessionPath) {
                    $logTextBox.Text = Get-FormattedSessionLog -SessionPath ([string]$result.SessionPath)
                    $logTextBox.ScrollToEnd()
                }
                $iconName = if ([bool]$result.Success) { 'Information' } else { 'Error' }
                [System.Windows.MessageBox]::Show($window, [string]$result.Message, 'Pulpo Custom Debloat', 'OK', $iconName) | Out-Null
            }).GetNewClosure())
            $timer.Start()
        }
        catch {
            Set-WindowBusy -Busy $false -Buttons $busyButtons -ProgressBar $progressBar
            $statusText.Text = $_.Exception.Message
            [System.Windows.MessageBox]::Show($window, $_.Exception.Message, 'Error de restauracion', 'OK', 'Error') | Out-Null
        }
    }).GetNewClosure())

    $systemRestoreButton.Add_Click({ Start-Process -FilePath 'rstrui.exe' })
    $openBackupsButton.Add_Click(({
        $backupRoot = Join-Path (Get-DebloatDataRoot) 'Backups'
        if (-not (Test-Path -LiteralPath $backupRoot -PathType Container)) {
            New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
        }
        Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $backupRoot)
    }).GetNewClosure())

    Set-ProfileSelection -Catalog $Catalog -ProfileId 'Safe' -ActionCheckBoxes $actionCheckBoxes -ServiceCheckBoxes $serviceCheckBoxes
    Update-SelectionSummary -TextBlock $selectionText -ActionCheckBoxes $actionCheckBoxes -ServiceCheckBoxes $serviceCheckBoxes
    $window.ShowDialog() | Out-Null
}

Export-ModuleMember -Function Show-DebloatWindow, Set-ProfileSelection, Clear-DebloatSelection, Update-SelectionSummary, Get-SelectedIds, Show-SelectionPreview, Get-FormattedSessionLog, Set-WindowBusy, Get-DebloatDataRoot, Save-DebloatJson, Read-DebloatJson
