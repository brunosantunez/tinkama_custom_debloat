[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $projectRoot 'src\Common.psm1')
Import-Module (Join-Path $projectRoot 'src\Registry.psm1')

$testId = [Guid]::NewGuid().ToString('N')
$registryPath = "HKCU:\Software\PulpoCustomDebloat\Tests\$testId"
$sessionPath = Join-Path ([System.IO.Path]::GetTempPath()) "PulpoCustomDebloat-Registry-$testId"
$context = New-DebloatContext -SessionPath $sessionPath
$null = New-Item -Path $registryPath -Force
$null = New-ItemProperty -LiteralPath $registryPath -Name 'Existing' -PropertyType String -Value 'original' -Force
$action = [pscustomobject]@{
    Id = 'RegistryIntegration'
    Title = 'Registry integration test'
    Registry = [object[]]@(
        [pscustomobject]@{ Path = $registryPath; Name = 'Number'; Type = 'DWord'; Value = 7 },
        [pscustomobject]@{ Path = $registryPath; Name = '@Default'; Type = 'ExpandString'; Value = '%TEMP%\Pulpo' },
        [pscustomobject]@{ Path = $registryPath; Name = 'Existing'; Type = 'DWord'; Value = 9 }
    )
}

try {
    $warningCount = Invoke-DebloatRegistryAction -Context $context -Action $action
    if ($warningCount -ne 0) {
        throw [System.InvalidOperationException]::new("La escritura temporal produjo $warningCount advertencias.")
    }

    $readKey = Get-Item -LiteralPath $registryPath
    try {
        if ($readKey.GetValueKind('Number') -ne [Microsoft.Win32.RegistryValueKind]::DWord -or
            $readKey.GetValue('Number') -ne 7 -or
            $readKey.GetValueKind('') -ne [Microsoft.Win32.RegistryValueKind]::ExpandString -or
            $readKey.GetValue('', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) -ne '%TEMP%\Pulpo' -or
            $readKey.GetValueKind('Existing') -ne [Microsoft.Win32.RegistryValueKind]::DWord -or
            $readKey.GetValue('Existing') -ne 9) {
            throw [System.IO.InvalidDataException]::new('Los valores temporales no conservaron su tipo o contenido.')
        }
    }
    finally {
        $readKey.Dispose()
    }

    Restore-DebloatRegistry -Context $context
    $restoredKey = Get-Item -LiteralPath $registryPath
    try {
        if ($restoredKey.GetValueNames().Count -ne 1 -or
            $restoredKey.GetValueKind('Existing') -ne [Microsoft.Win32.RegistryValueKind]::String -or
            $restoredKey.GetValue('Existing') -ne 'original') {
            throw [System.IO.InvalidDataException]::new('La restauracion no recupero el valor existente o no elimino los temporales.')
        }
    }
    finally {
        $restoredKey.Dispose()
    }

    [pscustomobject]@{
        NamedValueWritten = $true
        DefaultValueWritten = $true
        ExistingValueRestored = $true
        RegistryValuesRestored = $true
    } | Format-List
}
finally {
    if (Test-Path -LiteralPath $registryPath) {
        Remove-Item -LiteralPath $registryPath -Force
    }
    if (Test-Path -LiteralPath $sessionPath -PathType Container) {
        Remove-Item -LiteralPath $sessionPath -Recurse -Force
    }
}
