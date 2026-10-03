Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$script:Translations = @{
    en = @{
        'PERFIL' = 'PROFILE'
        'Basica segura' = 'Safe basic'
        'Taller completo' = 'Full workshop'
        'Captura agresiva' = 'Aggressive capture'
        '0 seleccionados' = '0 selected'
        'Ajustes' = 'Tweaks'
        'Aplicaciones' = 'Applications'
        'Servicios' = 'Services'
        'Herramientas' = 'Tools'
        'Restaurar y registro' = 'Restore and logs'
        'Depuracion' = 'Debug'
        'Ejecucion de scripts' = 'Script execution'
        'Preparar scripts' = 'Prepare scripts'
        'Descargas oficiales' = 'Official downloads'
        'Restaurar ultimo respaldo' = 'Restore latest backup'
        'Abrir Restaurar sistema' = 'Open System Restore'
        'Copiar informe' = 'Copy report'
        'Abrir informe' = 'Open report'
        'Listo para revisar' = 'Ready to review'
        'Previsualizar' = 'Preview'
        'Aplicar seleccion' = 'Apply selection'
        'Administrador' = 'Administrator'
        'Cambiar idioma' = 'Change language'
        'La restauracion interna recupera Registro, servicios y energia. Para aplicaciones eliminadas usa el punto de restauracion.' = 'Internal restore recovers Registry, services and power settings. For removed applications, use the system restore point.'
        'Servicios de impacto bajo' = 'Low-impact services'
        'Servicios opcionales' = 'Optional services'
        'Servicios con impacto funcional' = 'Services with functional impact'
        'Servicios de alto riesgo y protegidos' = 'High-risk and protected services'
        'BAJO' = 'LOW'
        'MEDIO' = 'MEDIUM'
        'ALTO' = 'HIGH'
        'CRITICO' = 'CRITICAL'
        'PROTEGIDO' = 'PROTECTED'
        'Privacidad' = 'Privacy'
        'Rendimiento' = 'Performance'
        'Sistema' = 'System'
        'Mantenimiento' = 'Maintenance'
    }
}

$script:TitleTranslations = @{
    en = @{
        privacy_general = 'General privacy'
        privacy_speech_inking = 'Speech and inking personalization'
        privacy_diagnostics = 'Feedback, diagnostics and telemetry'
        privacy_activity = 'Activity history'
        privacy_telemetry_tasks = 'Telemetry scheduled tasks'
        privacy_app_permissions = 'Application privacy permissions'
        privacy_background_apps = 'Background applications'
        privacy_location = 'Location and sensors'
        windows_suggestions = 'Suggestions, recommendations and tips'
        bing_search = 'Bing, Cortana and Search highlights'
        system_notifications = 'Windows and application notifications'
        storage_sense = 'Storage Sense'
        shared_experiences = 'Shared experiences'
        remote_access = 'Remote desktop and assistance'
        mobile_devices = 'Mobile devices and linking'
        driver_updates = 'Drivers outside Windows Update'
        delivery_optimization = 'Delivery Optimization'
        transparency = 'Transparency effects'
        visual_performance = 'Visual effects: thumbnails and fonts only'
        disable_prefetch = 'Disable Prefetch and Superfetch'
        game_bar = 'Game Bar, DVR and ms-gamingoverlay'
        ai_policies = 'Cortana, Copilot, Recall and AI features'
        custom_power_plan = 'Tinkama Custom high-performance plan'
        cleanup_temp = 'Clean Prefetch, Windows Temp and user Temp'
        disable_hibernation = 'Disable hibernation'
        disable_reserved_storage = 'Disable reserved storage'
        remove_onedrive = 'Uninstall OneDrive'
        disable_recall = 'Disable Recall feature'
        apps_bing = 'Bing and Weather'
        apps_help_start = 'Get Help and Get Started'
        apps_3d_office = '3D Viewer and preinstalled Office'
        apps_games_notes = 'Included games, Sticky Notes and Mixed Reality'
        apps_creative_communication = 'Paint 3D, People, Skype and Messaging'
        apps_maps_feedback_media = 'Maps, Feedback and Zune'
        apps_teams = 'Microsoft Teams'
        apps_xbox = 'Xbox and Gaming Overlay'
        apps_phone = 'Phone Link and Cross Device'
        apps_cortana_copilot = 'Cortana and Copilot packages'
        apps_widgets = 'Widgets and Windows Web Experience'
        svc_diagtrack = 'Connected User Experiences and Telemetry'
        svc_dmwappush = 'WAP Push Message Routing Service'
        svc_maps = 'Downloaded Maps Manager'
        svc_retail = 'Retail Demo Service'
        svc_remote_registry = 'Remote Registry'
        svc_location = 'Geolocation Service'
        svc_diagnostics = 'Diagnostic System Host'
        svc_assigned_access = 'Assigned Access Manager'
        svc_shared_pc = 'Shared PC Account Manager'
        svc_data_usage = 'Data Usage'
        svc_dps = 'Diagnostic Policy Service'
        svc_wdi_host = 'Diagnostic Service Host'
        svc_wdi_system = 'Diagnostic System Host'
        svc_diagsvc = 'Diagnostic Execution Service'
        svc_wer = 'Windows Error Reporting'
        svc_wer_support = 'Problem Reports and Solutions Control Panel Support'
        svc_performance_logs = 'Performance Logs and Alerts'
        svc_pca = 'Program Compatibility Assistant Service'
        svc_sysmain = 'SysMain / Prefetch'
        svc_ai_fabric = 'Windows AI Fabric'
        svc_notifications = 'Windows Push Notifications System Service'
        svc_notifications_user = 'Windows Push Notifications User Service'
        svc_phone = 'Phone Service'
        svc_cdp = 'Connected Devices Platform Service'
        svc_cdp_user = 'Connected Devices Platform User Service'
        svc_device_flow = 'DeviceFlow'
        svc_contact_index = 'Contact Data'
        svc_sync = 'Sync Host'
        svc_messaging = 'Messaging Service'
        svc_xbl_auth = 'Xbox Live Auth Manager'
        svc_xbl_save = 'Xbox Live Game Save'
        svc_xbox_network = 'Xbox Live Networking Service'
        svc_xbox_accessory = 'Xbox Accessory Management Service'
        svc_remote_desktop = 'Remote Desktop Services'
        svc_routing = 'Routing and Remote Access'
        svc_net_tcp = 'Net.Tcp Port Sharing Service'
        svc_uev = 'User Experience Virtualization'
        svc_dialog_blocking = 'Dialog Blocking Service'
        svc_appv = 'Microsoft App-V Client'
        svc_keyboard_filter = 'Microsoft Keyboard Filter'
        svc_open_ssh = 'OpenSSH Authentication Agent'
        svc_game_input = 'GameInput Service'
        svc_camera = 'Windows Camera Frame Server'
        svc_search = 'Windows Search'
        svc_print = 'Print Spooler'
        svc_shared_access = 'Internet Connection Sharing'
        svc_edge_update = 'Microsoft Edge Update'
        svc_edge_update_machine = 'Microsoft Edge Update Service'
        svc_mt_agent = 'MT Agent Service'
        svc_mt_scheduler = 'MT Scheduler Service'
        svc_display_policy = 'Display Policy Service'
        svc_group_policy = 'Group Policy Client'
    }
}

function Get-TinkamaLanguagePath {
    [OutputType([string])]
    param()
    return (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TinkamaCustomDebloat\language.txt')
}

function Get-TinkamaLanguage {
    [OutputType([string])]
    param()
    $path = Get-TinkamaLanguagePath
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $value = (Get-Content -LiteralPath $path -Raw).Trim().ToLowerInvariant()
        if ($value -in @('es', 'en')) { return $value }
    }
    return 'es'
}

function Set-TinkamaLanguage {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('es', 'en')]
        [string]$Language
    )
    $path = Get-TinkamaLanguagePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    Set-Content -LiteralPath $path -Value $Language -Encoding ASCII
}

function Get-TinkamaText {
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string]$Text,
        [Parameter(Mandatory)] [ValidateSet('es', 'en')] [string]$Language
    )
    if ($Language -eq 'en' -and $script:Translations.en.ContainsKey($Text)) {
        return [string]$script:Translations.en[$Text]
    }
    return $Text
}

function Get-TinkamaEntryTitle {
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [pscustomobject]$Entry,
        [Parameter(Mandatory)] [ValidateSet('es', 'en')] [string]$Language
    )
    if ($Language -eq 'en' -and $script:TitleTranslations.en.ContainsKey([string]$Entry.Id)) {
        return [string]$script:TitleTranslations.en[[string]$Entry.Id]
    }
    return [string]$Entry.Title
}

function Show-TinkamaLanguageSelection {
    [OutputType([string])]
    param()
    Add-Type -AssemblyName PresentationFramework
    $window = [System.Windows.Window]::new()
    $window.Title = 'Tinkama Custom Debloat'
    $window.Width = 420
    $window.Height = 210
    $window.ResizeMode = [System.Windows.ResizeMode]::NoResize
    $window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
    $window.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#111111')
    $window.Foreground = [System.Windows.Media.Brushes]::White
    $panel = [System.Windows.Controls.StackPanel]::new()
    $panel.Margin = [System.Windows.Thickness]::new(24)
    $title = [System.Windows.Controls.TextBlock]::new()
    $title.Text = 'Select language / Seleccione idioma'
    $title.FontSize = 20
    $title.FontWeight = [System.Windows.FontWeights]::SemiBold
    $panel.Children.Add($title) | Out-Null
    $message = [System.Windows.Controls.TextBlock]::new()
    $message.Text = 'Choose the language for the interface. / Elija el idioma de la interfaz.'
    $message.Margin = [System.Windows.Thickness]::new(0, 12, 0, 18)
    $message.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#C9C9C9')
    $panel.Children.Add($message) | Out-Null
    $buttons = [System.Windows.Controls.StackPanel]::new()
    $buttons.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $buttons.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
    foreach ($choice in @([pscustomobject]@{ Code = 'es'; Label = 'Espanol' }, [pscustomobject]@{ Code = 'en'; Label = 'English' })) {
        $button = [System.Windows.Controls.Button]::new()
        $button.Content = $choice.Label
        $button.Tag = $choice.Code
        $button.Width = 110
        $button.Height = 38
        $button.Margin = [System.Windows.Thickness]::new(0, 0, 10, 0)
        $button.Add_Click(({
            param($sender, $eventArgs)
            $window.Tag = [string]$sender.Tag
            $window.DialogResult = $true
        }.GetNewClosure()))
        $buttons.Children.Add($button) | Out-Null
    }
    $panel.Children.Add($buttons) | Out-Null
    $window.Content = $panel
    if ($window.ShowDialog() -ne $true) { return $null }
    return [string]$window.Tag
}

function Convert-TinkamaStaticElement {
    param(
        [Parameter(Mandatory)] [System.Windows.DependencyObject]$Element,
        [Parameter(Mandatory)] [ValidateSet('es', 'en')] [string]$Language
    )
    if ($Element -is [System.Windows.Controls.TextBlock]) {
        $Element.Text = Get-TinkamaText -Text $Element.Text -Language $Language
    }
    if ($Element -is [System.Windows.Controls.TabItem]) {
        $Element.Header = Get-TinkamaText -Text ([string]$Element.Header) -Language $Language
    }
    foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($Element)) {
        if ($child -is [System.Windows.DependencyObject]) {
            Convert-TinkamaStaticElement -Element $child -Language $Language
        }
    }
}

function Set-TinkamaStaticLocalization {
    param(
        [Parameter(Mandatory)] [System.Windows.Window]$Window,
        [Parameter(Mandatory)] [ValidateSet('es', 'en')] [string]$Language
    )
    if ($Language -eq 'es') { return }
    Convert-TinkamaStaticElement -Element $Window -Language $Language
}

Export-ModuleMember -Function Get-TinkamaLanguagePath, Get-TinkamaLanguage, Set-TinkamaLanguage, Get-TinkamaText, Get-TinkamaEntryTitle, Show-TinkamaLanguageSelection, Set-TinkamaStaticLocalization
