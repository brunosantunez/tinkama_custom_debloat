[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$projectRoot = $PSScriptRoot
try {
    Import-Module (Join-Path $projectRoot 'src\Execution.psm1')
    Import-Module (Join-Path $projectRoot 'src\Localization.psm1')
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $isAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $requiresNativeHost = $PSVersionTable.PSEdition -ne 'Desktop' -or
        ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) -or
        [Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'

    if (-not $isAdministrator -or $requiresNativeHost) {
        $arguments = @('-NoLogo', '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath))
        $launch = @{
            FilePath = Get-DebloatPowerShellPath
            ArgumentList = $arguments
            WorkingDirectory = $projectRoot
            WindowStyle = 'Hidden'
            PassThru = $true
        }
        if (-not $isAdministrator) {
            $launch.Verb = 'RunAs'
        }
        Start-Process @launch | Out-Null
        exit 0
    }

    $languagePath = Get-TinkamaLanguagePath
    if (-not (Test-Path -LiteralPath $languagePath -PathType Leaf)) {
        $selectedLanguage = Show-TinkamaLanguageSelection
        if ([string]::IsNullOrWhiteSpace($selectedLanguage)) { exit 0 }
        Set-TinkamaLanguage -Language $selectedLanguage
    }
    $language = Get-TinkamaLanguage

    if (-not (Show-DebloatScriptConsent)) {
        exit 0
    }
    Enable-DebloatSessionScripts -ProjectRoot $projectRoot | Out-Null
    Import-Module (Join-Path $projectRoot 'src\Catalog.psm1')
    Import-Module (Join-Path $projectRoot 'src\UserInterface.psm1')
    $catalog = Import-DebloatCatalog -Path (Join-Path $projectRoot 'config\catalog.json')
    Show-DebloatWindow -ProjectRoot $projectRoot -Catalog $catalog -Language $language
}
catch {
    $failure = $_
    $logRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TinkamaCustomDebloat\Logs'
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    $logPath = Join-Path $logRoot ('startup-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    ($failure | Format-List * -Force | Out-String) + [Environment]::NewLine + $failure.ScriptStackTrace | Set-Content -LiteralPath $logPath -Encoding UTF8
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show("$($failure.Exception.Message)$([Environment]::NewLine)Registro: $logPath", 'Tinkama Custom Debloat - Error de inicio', 'OK', 'Error') | Out-Null
    exit 1
}
