[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$os = Get-CimInstance -ClassName Win32_OperatingSystem
if ([int]$os.BuildNumber -lt 22000) {
    throw [System.PlatformNotSupportedException]::new("Este ajuste requiere Windows 11. Build detectado: $($os.BuildNumber)")
}

$classId = '{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}'
$path = "HKCU:\Software\Classes\CLSID\$classId\InprocServer32"
if (-not (Test-Path -LiteralPath $path)) {
    New-Item -Path $path -Force | Out-Null
}

$key = Get-Item -LiteralPath $path
try {
    $key.SetValue('', '', [Microsoft.Win32.RegistryValueKind]::String)
    if ($key.GetValue('', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) -ne '') {
        throw [System.IO.InvalidDataException]::new("No se pudo verificar el valor predeterminado de $path")
    }
}
finally {
    $key.Dispose()
}

$explorerProcesses = @(Get-Process -Name 'explorer' -ErrorAction SilentlyContinue)
foreach ($process in $explorerProcesses) {
    Stop-Process -Id $process.Id -Force
}
Start-Sleep -Seconds 1
if (@(Get-Process -Name 'explorer' -ErrorAction SilentlyContinue).Count -eq 0) {
    Start-Process -FilePath 'explorer.exe'
}
Write-Output 'Menu contextual clasico habilitado y Explorador de Windows reiniciado.'
