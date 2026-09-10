[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$archiveUri = 'https://github.com/brunosantunez/pulpo_custom_debloat/archive/refs/heads/main.zip'
$installRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'PulpoCustomDebloat'
$currentPath = Join-Path $installRoot 'current'
$stagingPath = Join-Path $installRoot ('staging-{0}' -f [Guid]::NewGuid().ToString('N'))
$archivePath = Join-Path $stagingPath 'source.zip'
$extractPath = Join-Path $stagingPath 'source'

New-Item -ItemType Directory -Path $stagingPath -Force | Out-Null

try {
    Invoke-WebRequest -Uri $archiveUri -UseBasicParsing -OutFile $archivePath
    Unblock-File -LiteralPath $archivePath
    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath -Force

    $sourceDirectories = @(Get-ChildItem -LiteralPath $extractPath -Directory)
    if ($sourceDirectories.Count -ne 1) {
        throw [System.IO.InvalidDataException]::new(
            'El archivo descargado debe contener exactamente una carpeta raiz; se encontraron {0}.' -f $sourceDirectories.Count
        )
    }

    $sourcePath = $sourceDirectories[0].FullName
    $requiredPaths = @(
        'PulpoCustomDebloat.ps1'
        'config\catalog.json'
        'ui\MainWindow.xaml'
        'src\Engine.psm1'
    )

    foreach ($requiredPath in $requiredPaths) {
        $candidatePath = Join-Path $sourcePath $requiredPath
        if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
            throw [System.IO.InvalidDataException]::new(
                'La descarga no contiene el archivo requerido: {0}' -f $requiredPath
            )
        }
    }

    $fullInstallRoot = [System.IO.Path]::GetFullPath($installRoot).TrimEnd('\')
    $fullCurrentPath = [System.IO.Path]::GetFullPath($currentPath)
    $expectedPrefix = $fullInstallRoot + [System.IO.Path]::DirectorySeparatorChar
    if (-not $fullCurrentPath.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw [System.IO.IOException]::new('La ruta de instalacion calculada esta fuera del directorio permitido.')
    }

    if (Test-Path -LiteralPath $currentPath) {
        Remove-Item -LiteralPath $currentPath -Recurse -Force
    }

    Move-Item -LiteralPath $sourcePath -Destination $currentPath

    $entryPoint = Join-Path $currentPath 'PulpoCustomDebloat.ps1'
    $arguments = @(
        '-NoLogo'
        '-NoProfile'
        '-STA'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        ('"{0}"' -f $entryPoint)
    )
    Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WorkingDirectory $currentPath -WindowStyle Hidden
}
finally {
    if (Test-Path -LiteralPath $stagingPath) {
        Remove-Item -LiteralPath $stagingPath -Recurse -Force
    }
}
