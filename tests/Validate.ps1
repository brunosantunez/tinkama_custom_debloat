[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$scriptFiles = @(
    Get-ChildItem -LiteralPath $projectRoot -Recurse -File |
        Where-Object Extension -in @('.ps1', '.psm1')
)
$parseFailures = [System.Collections.Generic.List[string]]::new()

foreach ($file in $scriptFiles) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    foreach ($parseError in @($parseErrors)) {
        $parseFailures.Add("$($file.FullName):$($parseError.Extent.StartLineNumber) $($parseError.Message)")
    }
}
if ($parseFailures.Count -gt 0) {
    throw [System.Management.Automation.ParseException]::new("Errores de sintaxis: $($parseFailures -join ' | ')")
}

Import-Module (Join-Path $projectRoot 'src\Catalog.psm1')
$catalog = Import-DebloatCatalog -Path (Join-Path $projectRoot 'config\catalog.json')

$protectedServices = @($catalog.Services | Where-Object Protected | Select-Object -ExpandProperty Id)
foreach ($profile in @($catalog.Profiles)) {
    $invalid = @($profile.ServiceIds | Where-Object { $_ -in $protectedServices })
    if ($invalid.Count -gt 0) {
        throw [System.IO.InvalidDataException]::new("El perfil $($profile.Id) contiene servicios protegidos: $($invalid -join ', ')")
    }
}

$protectedPackages = @(
    'Microsoft.DesktopAppInstaller', 'Microsoft.SecHealthUI', 'Microsoft.WindowsStore',
    'MicrosoftWindows.Client.CBS', 'MicrosoftWindows.Client.Core'
)
foreach ($action in @($catalog.Actions | Where-Object Kind -eq 'Packages')) {
    foreach ($pattern in @($action.PackagePatterns)) {
        $matches = @($protectedPackages | Where-Object { $_ -like $pattern })
        if ($matches.Count -gt 0) {
            throw [System.IO.InvalidDataException]::new("La accion $($action.Id) coincide con paquetes protegidos: $($matches -join ', ')")
        }
    }
}

Add-Type -AssemblyName PresentationFramework
[xml]$xaml = Get-Content -LiteralPath (Join-Path $projectRoot 'ui\MainWindow.xaml') -Raw
$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
$requiredControls = @(
    'SettingsPanel', 'AppsPanel', 'ServicesPanel', 'ToolsPanel', 'SelectionText',
    'StatusText', 'WorkProgress', 'ApplyButton', 'RestoreSettingsButton', 'LogTextBox', 'PrepareScriptsButton'
)
foreach ($name in $requiredControls) {
    if ($null -eq $window.FindName($name)) {
        throw [System.InvalidOperationException]::new("Falta el control WPF requerido: $name")
    }
}
$window.Close()

Import-Module (Join-Path $projectRoot 'src\UserInterface.psm1')
Import-Module (Join-Path $projectRoot 'src\Engine.psm1')

[pscustomobject]@{
    ScriptsParsed = $scriptFiles.Count
    Actions = $catalog.Actions.Count
    Services = $catalog.Services.Count
    Profiles = $catalog.Profiles.Count
    Tools = $catalog.Tools.Count
    WpfControls = $requiredControls.Count
} | Format-List
