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

$classicMenuAction = @($catalog.Actions | Where-Object Id -eq 'classic_context_menu')
if ($classicMenuAction.Count -ne 1 -or $classicMenuAction[0].Handler -ne 'EnableClassicContextMenu') {
    throw [System.IO.InvalidDataException]::new('Falta la accion valida para el menu contextual clasico de Windows 11.')
}
foreach ($profile in @($catalog.Profiles)) {
    if ('classic_context_menu' -notin $profile.ActionIds) {
        throw [System.IO.InvalidDataException]::new("El perfil $($profile.Id) no incluye el menu contextual clasico.")
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
    'StatusText', 'WorkProgress', 'ApplyButton', 'RestoreSettingsButton', 'LogTextBox', 'PrepareScriptsButton',
    'DebugTextBox', 'CopyDebugButton', 'OpenDebugReportButton'
)
foreach ($name in $requiredControls) {
    if ($null -eq $window.FindName($name)) {
        throw [System.InvalidOperationException]::new("Falta el control WPF requerido: $name")
    }
}
$window.Close()

Import-Module (Join-Path $projectRoot 'src\UserInterface.psm1')
Import-Module (Join-Path $projectRoot 'src\Engine.psm1')

$selectionCases = @(
    @{ Expected = [string[]]@(); CheckBoxes = @{ first = [pscustomobject]@{ IsChecked = $false } } },
    @{ Expected = [string[]]@('first'); CheckBoxes = @{ first = [pscustomobject]@{ IsChecked = $true } } },
    @{ Expected = [string[]]@('first', 'second'); CheckBoxes = @{
        second = [pscustomobject]@{ IsChecked = $true }
        first = [pscustomobject]@{ IsChecked = $true }
    } }
)
foreach ($selectionCase in $selectionCases) {
    [string[]]$selectedIds = Get-SelectedIds -CheckBoxes $selectionCase.CheckBoxes
    $selectionJson = [pscustomobject]@{ ActionIds = $selectedIds } | ConvertTo-Json -Depth 3
    $serializedIds = ($selectionJson | ConvertFrom-Json).ActionIds
    if ($selectedIds.GetType() -ne [string[]] -or
        @($serializedIds).Count -ne $selectionCase.Expected.Count -or
        (@($serializedIds) -join ',') -ne ($selectionCase.Expected -join ',')) {
        throw [System.IO.InvalidDataException]::new("La seleccion no conserva el contrato JSON: $selectionJson")
    }
}

[pscustomobject]@{
    ScriptsParsed = $scriptFiles.Count
    Actions = $catalog.Actions.Count
    Services = $catalog.Services.Count
    Profiles = $catalog.Profiles.Count
    Tools = $catalog.Tools.Count
    WpfControls = $requiredControls.Count
} | Format-List
