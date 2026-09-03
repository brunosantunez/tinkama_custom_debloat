[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$projectRoot = $PSScriptRoot
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdministrator) {
    $arguments = @(
        '-NoLogo'
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        ('"{0}"' -f $PSCommandPath)
    )
    Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs -WorkingDirectory $projectRoot
    exit 0
}

Import-Module (Join-Path $projectRoot 'src\Catalog.psm1') -Force
Import-Module (Join-Path $projectRoot 'src\UserInterface.psm1') -Force

$catalogPath = Join-Path $projectRoot 'config\catalog.json'
$catalog = Import-DebloatCatalog -Path $catalogPath
Show-DebloatWindow -ProjectRoot $projectRoot -Catalog $catalog
