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

function Write-DebloatNotApplied {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context,

        [Parameter(Mandatory)]
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Component,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Instruction,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Command,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Reason,

        [Parameter(Mandatory)]
        [hashtable]$Data
    )

    $diagnosticData = @{}
    foreach ($key in $Data.Keys) {
        $diagnosticData[$key] = $Data[$key]
    }
    $diagnosticData.Outcome = 'NotApplied'
    $diagnosticData.Instruction = $Instruction
    $diagnosticData.Command = $Command
    $diagnosticData.Reason = $Reason
    Write-DebloatLog -Context $Context -Level $Level -Component $Component -Message $Reason -Data $diagnosticData
}

function ConvertTo-DebloatPowerShellLiteral {
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return '$null'
    }
    if ($Value -is [bool]) {
        return $(if ($Value) { '$true' } else { '$false' })
    }
    if ($Value -is [System.Array]) {
        $items = @($Value | ForEach-Object { ConvertTo-DebloatPowerShellLiteral -Value $_ })
        return "@($($items -join ', '))"
    }
    if ($Value -is [string] -or $Value -is [char]) {
        return "'$(([string]$Value).Replace("'", "''"))'"
    }
    if ($Value -is [System.IFormattable]) {
        return $Value.ToString($null, [System.Globalization.CultureInfo]::InvariantCulture)
    }
    return "'$(([string]$Value).Replace("'", "''"))'"
}

function Read-DebloatSharedTextFile {
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $lastError = $null
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            $stream = [System.IO.FileStream]::new(
                [System.IO.Path]::GetFullPath($Path),
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
            )
            $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)
            try {
                return $reader.ReadToEnd()
            }
            finally {
                $reader.Dispose()
            }
        }
        catch [System.IO.IOException] {
            $lastError = $_.Exception
            if ($attempt -lt 5) {
                Start-Sleep -Milliseconds 20
            }
        }
    }
    throw [System.IO.IOException]::new("No se pudo leer el registro compartido despues de 5 intentos: $Path", $lastError)
}

function Read-DebloatLogEntries {
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SessionPath
    )

    $logPath = Join-Path $SessionPath 'operations.jsonl'
    if (-not (Test-Path -LiteralPath $logPath -PathType Leaf)) {
        return [object[]]@()
    }

    $content = Read-DebloatSharedTextFile -Path $logPath
    $rawLines = @($content -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $entries = [System.Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $rawLines.Count; $index++) {
        try {
            $entries.Add(($rawLines[$index] | ConvertFrom-Json))
        }
        catch {
            if ($index -eq $rawLines.Count - 1 -and -not $content.EndsWith("`n")) {
                break
            }
            throw [System.IO.InvalidDataException]::new("El registro contiene una linea JSON invalida: $logPath", $_.Exception)
        }
    }
    return [object[]]$entries
}

function Get-DebloatDebugReport {
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SessionPath
    )

    $diagnostics = @(
        Read-DebloatLogEntries -SessionPath $SessionPath |
            Where-Object {
                ($_.Data.PSObject.Properties.Name -contains 'Outcome' -and $_.Data.Outcome -eq 'NotApplied') -or
                $_.Level -eq 'Error'
            }
    )
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('Pulpo Custom Debloat - Informe de depuracion')
    $lines.Add("Sesion: $SessionPath")
    $lines.Add("Cambios no efectuados: $($diagnostics.Count)")
    $lines.Add('')

    foreach ($entry in $diagnostics) {
        $instruction = if ($entry.Data.PSObject.Properties.Name -contains 'Instruction') { [string]$entry.Data.Instruction } else { [string]$entry.Message }
        $command = if ($entry.Data.PSObject.Properties.Name -contains 'Command') { [string]$entry.Data.Command } else { 'Comando no registrado' }
        $reason = if ($entry.Data.PSObject.Properties.Name -contains 'Reason') { [string]$entry.Data.Reason } else { [string]$entry.Message }
        $time = [DateTime]::Parse($entry.TimestampUtc).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss')
        $lines.Add("[$time] [$($entry.Level)] [$($entry.Component)]")
        $lines.Add("Instruccion: $instruction")
        $lines.Add("Comando: $command")
        $lines.Add("Motivo: $reason")
        $lines.Add('')
    }
    if ($diagnostics.Count -eq 0) {
        $lines.Add('No se registraron cambios sin efectuar.')
    }

    return [pscustomobject]@{
        Count = $diagnostics.Count
        Text = $lines -join [Environment]::NewLine
    }
}

function Save-DebloatDebugReport {
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SessionPath
    )

    $report = Get-DebloatDebugReport -SessionPath $SessionPath
    $path = Join-Path $SessionPath 'debug-report.txt'
    Set-Content -LiteralPath $path -Value $report.Text -Encoding UTF8
    return $path
}

function Enter-DebloatJsonLock {
    [OutputType([System.Threading.Mutex])]
    param()

    $mutex = [System.Threading.Mutex]::new($false, 'Local\PulpoCustomDebloat.Json')
    try {
        if (-not $mutex.WaitOne(15000)) {
            throw [System.TimeoutException]::new('No se obtuvo el bloqueo de datos de Pulpo Custom Debloat en 15 segundos.')
        }
        return $mutex
    }
    catch [System.Threading.AbandonedMutexException] {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
        throw [System.IO.InvalidDataException]::new('El proceso anterior interrumpio una escritura. Revisa los registros antes de volver a aplicar cambios.', $_.Exception)
    }
    catch {
        $mutex.Dispose()
        throw
    }
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

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $temporaryPath = '{0}.{1}.tmp' -f $fullPath, [Guid]::NewGuid().ToString('N')
    $json = ConvertTo-Json -InputObject $InputObject -Depth 12
    $mutex = Enter-DebloatJsonLock
    try {
        [System.IO.File]::WriteAllText($temporaryPath, $json, [System.Text.UTF8Encoding]::new($false))
        # Publish complete documents; readers must never observe a truncated JSON file.
        if ([System.IO.File]::Exists($fullPath)) {
            [System.IO.File]::Replace($temporaryPath, $fullPath, [System.Management.Automation.Language.NullString]::Value)
        }
        else {
            [System.IO.File]::Move($temporaryPath, $fullPath)
        }
    }
    finally {
        try {
            if ([System.IO.File]::Exists($temporaryPath)) {
                [System.IO.File]::Delete($temporaryPath)
            }
        }
        finally {
            $mutex.ReleaseMutex()
            $mutex.Dispose()
        }
    }
}

function Read-DebloatJson {
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $mutex = Enter-DebloatJsonLock
    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw [System.IO.FileNotFoundException]::new("No se encontro el archivo JSON: $Path")
        }
        $stream = [System.IO.FileStream]::new(
            [System.IO.Path]::GetFullPath($Path),
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
        )
        $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)
        try {
            $json = $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }
        if ([string]::IsNullOrWhiteSpace($json)) {
            throw [System.IO.InvalidDataException]::new('El documento esta vacio.')
        }
        $parsed = ConvertFrom-Json -InputObject $json
        if ($parsed -is [System.Array]) {
            foreach ($item in [object[]]$parsed) {
                Write-Output $item
            }
            return
        }
        return $parsed
    }
    catch {
        throw [System.IO.InvalidDataException]::new("El archivo JSON no es valido: $Path. $($_.Exception.Message)", $_.Exception)
    }
    finally {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
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
    try {
        if (-not $process.Start()) {
            throw [System.InvalidOperationException]::new("No se pudo iniciar $FilePath $Arguments")
        }

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill()
            $process.WaitForExit()
            $stdoutTask.GetAwaiter().GetResult() | Out-Null
            $stderrTask.GetAwaiter().GetResult() | Out-Null
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
    finally {
        $process.Dispose()
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

Export-ModuleMember -Function Test-DebloatAdministrator, Get-DebloatDataRoot, New-DebloatContext, Write-DebloatLog, Write-DebloatNotApplied, ConvertTo-DebloatPowerShellLiteral, Read-DebloatSharedTextFile, Read-DebloatLogEntries, Get-DebloatDebugReport, Save-DebloatDebugReport, Save-DebloatJson, Read-DebloatJson, Invoke-DebloatNativeCommand, Assert-DebloatSupportedSystem
