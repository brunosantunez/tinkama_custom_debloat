Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Test-DebloatAdministrator {
    [OutputType([bool])]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-DebloatDataRoot {
    [OutputType([string])]
    param()

    return Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'PulpoCustomDebloat'
}

function New-DebloatContext {
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SessionPath
    )

    return [pscustomobject]@{
        SessionPath = $SessionPath
        LogPath = Join-Path $SessionPath 'operations.jsonl'
    }
}

function Write-DebloatLog {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context,

        [Parameter(Mandatory)]
        [ValidateSet('Debug', 'Info', 'Warning', 'Error', 'Success')]
        [string]$Level,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Component,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory)]
        [hashtable]$Data
    )

    if (-not (Test-Path -LiteralPath $Context.SessionPath -PathType Container)) {
        New-Item -ItemType Directory -Path $Context.SessionPath -Force | Out-Null
    }

    $entry = [ordered]@{
        TimestampUtc = [DateTime]::UtcNow.ToString('o')
        Level = $Level
        Component = $Component
        Message = $Message
        Data = $Data
    }
    $entry | ConvertTo-Json -Compress -Depth 8 | Add-Content -LiteralPath $Context.LogPath -Encoding UTF8
}

function Save-DebloatJson {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $temporaryPath = "$Path.tmp"
    ConvertTo-Json -InputObject $InputObject -Depth 12 | Set-Content -LiteralPath $temporaryPath -Encoding UTF8
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Read-DebloatJson {
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw [System.IO.FileNotFoundException]::new("No se encontro el archivo JSON: $Path")
    }

    try {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    catch {
        throw [System.IO.InvalidDataException]::new("El archivo JSON no es valido: $Path. $($_.Exception.Message)", $_.Exception)
    }
}

function Invoke-DebloatNativeCommand {
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Arguments,

        [Parameter(Mandatory)]
        [ValidateRange(1, 3600)]
        [int]$TimeoutSeconds,

        [Parameter(Mandatory)]
        [int[]]$AllowedExitCodes
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = $Arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw [System.InvalidOperationException]::new("No se pudo iniciar $FilePath $Arguments")
    }

    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        $process.Kill()
        throw [System.TimeoutException]::new("El comando excedio $TimeoutSeconds segundos: $FilePath $Arguments")
    }

    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    if ($process.ExitCode -notin $AllowedExitCodes) {
        throw [System.ComponentModel.Win32Exception]::new("El comando fallo con codigo $($process.ExitCode): $FilePath $Arguments. Salida: $stdout Error: $stderr")
    }

    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        StandardOutput = $stdout
        StandardError = $stderr
    }
}

function Assert-DebloatSupportedSystem {
    param()

    if (-not (Test-DebloatAdministrator)) {
        throw [System.UnauthorizedAccessException]::new('Pulpo Custom Debloat requiere una sesion elevada como administrador.')
    }

    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    if ($os.ProductType -ne 1) {
        throw [System.PlatformNotSupportedException]::new("Solo se admiten ediciones cliente de Windows. ProductType detectado: $($os.ProductType)")
    }

    $build = [int]$os.BuildNumber
    if ($build -lt 17763) {
        throw [System.PlatformNotSupportedException]::new("Se requiere Windows 10 1809 o posterior. Build detectado: $build")
    }
}

Export-ModuleMember -Function Test-DebloatAdministrator, Get-DebloatDataRoot, New-DebloatContext, Write-DebloatLog, Save-DebloatJson, Read-DebloatJson, Invoke-DebloatNativeCommand, Assert-DebloatSupportedSystem
