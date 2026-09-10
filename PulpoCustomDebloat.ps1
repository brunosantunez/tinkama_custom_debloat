[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$projectRoot = $PSScriptRoot
try {
    Import-Module (Join-Path $projectRoot 'src\Execution.psm1')
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

    if (-not (Show-DebloatScriptConsent)) {
        exit 0
    }
    Enable-DebloatSessionScripts -ProjectRoot $projectRoot | Out-Null
    Import-Module (Join-Path $projectRoot 'src\Catalog.psm1')
    Import-Module (Join-Path $projectRoot 'src\UserInterface.psm1')
    $catalog = Import-DebloatCatalog -Path (Join-Path $projectRoot 'config\catalog.json')
    Show-DebloatWindow -ProjectRoot $projectRoot -Catalog $catalog
}
catch {
    $failure = $_
    $logRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'PulpoCustomDebloat\Logs'
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    $logPath = Join-Path $logRoot ('startup-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    ($failure | Format-List * -Force | Out-String) + [Environment]::NewLine + $failure.ScriptStackTrace | Set-Content -LiteralPath $logPath -Encoding UTF8
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show("$($failure.Exception.Message)$([Environment]::NewLine)Registro: $logPath", 'Pulpo Custom Debloat - Error de inicio', 'OK', 'Error') | Out-Null
    exit 1
}
