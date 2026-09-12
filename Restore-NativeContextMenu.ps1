[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$subKey = 'Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}'
$path = "HKCU:\$subKey"
if (Test-Path -LiteralPath $path) {
    $backupRoot = Join-Path $env:LOCALAPPDATA 'PulpoCustomDebloat\Backups'
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $backupPath = Join-Path $backupRoot ("ContextMenu-{0}.reg" -f [Guid]::NewGuid().ToString('N'))
    & reg.exe export "HKCU\$subKey" $backupPath /y
    if ($LASTEXITCODE -ne 0) {
        throw [System.IO.IOException]::new("No se pudo respaldar $path. Codigo: $LASTEXITCODE. No se retiro el ajuste.")
    }
    # Only remove the fixed CLSID used by the retired context-menu tweak.
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($subKey)
    if (Test-Path -LiteralPath $path) {
        throw [System.IO.IOException]::new("Windows no elimino el ajuste en $path.")
    }
    Write-Output "Ajuste de menu clasico retirado. Respaldo: $backupPath. Cierra y abre sesion para cargar el menu nativo."
}
else {
    Write-Output 'El ajuste de menu clasico no esta presente para este usuario.'
}
