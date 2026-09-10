Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Assert-RequiredString {
    param(
        [Parameter(Mandatory)]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$Field,

        [Parameter(Mandatory)]
        [string]$Owner
    )

    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        throw [System.IO.InvalidDataException]::new("$Owner requiere el campo de texto '$Field'.")
    }
}

function Import-DebloatCatalog {
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw [System.IO.FileNotFoundException]::new("No se encontro el catalogo: $Path")
    }

    try {
        $catalog = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    catch {
        throw [System.IO.InvalidDataException]::new("El catalogo no es JSON valido: $Path. $($_.Exception.Message)", $_.Exception)
    }

    if ([int]$catalog.Version -ne 1) {
        throw [System.IO.InvalidDataException]::new("Version de catalogo no admitida: $($catalog.Version)")
    }

    $allowedKinds = @('Registry', 'Packages', 'Special')
    $allowedRisks = @('Low', 'Medium', 'High', 'Critical')
    $allowedRegistryTypes = @('DWord', 'QWord', 'String', 'ExpandString', 'MultiString', 'Binary')
    $allowedHandlers = @('SetCustomPowerPlan', 'CleanTemporaryFiles', 'DisableHibernation', 'DisableReservedStorage', 'RemoveOneDrive', 'DisableRecall', 'DisableTelemetryTasks')
    $actionIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    foreach ($action in @($catalog.Actions)) {
        foreach ($field in @('Id', 'Title', 'Description', 'Category', 'Kind', 'Risk')) {
            Assert-RequiredString -Value $action.$field -Field $field -Owner 'Action'
        }
        if (-not $actionIds.Add([string]$action.Id)) {
            throw [System.IO.InvalidDataException]::new("Id de accion duplicado: $($action.Id)")
        }
        if ($action.Kind -notin $allowedKinds) {
            throw [System.IO.InvalidDataException]::new("Kind no admitido en $($action.Id): $($action.Kind)")
        }
        if ($action.Risk -notin $allowedRisks) {
            throw [System.IO.InvalidDataException]::new("Risk no admitido en $($action.Id): $($action.Risk)")
        }

        if ($action.Kind -eq 'Registry') {
            if (@($action.Registry).Count -eq 0) {
                throw [System.IO.InvalidDataException]::new("La accion $($action.Id) no contiene operaciones Registry.")
            }
            foreach ($operation in @($action.Registry)) {
                Assert-RequiredString -Value $operation.Path -Field 'Path' -Owner $action.Id
                Assert-RequiredString -Value $operation.Name -Field 'Name' -Owner $action.Id
                Assert-RequiredString -Value $operation.Type -Field 'Type' -Owner $action.Id
                if ($operation.Type -notin $allowedRegistryTypes) {
                    throw [System.IO.InvalidDataException]::new("Tipo de Registro no admitido en $($action.Id): $($operation.Type)")
                }
                if ($operation.Path -notmatch '^(HKCU:|HKLM:)\\') {
                    throw [System.IO.InvalidDataException]::new("Ruta de Registro fuera de alcance en $($action.Id): $($operation.Path)")
                }
                if ($null -eq $operation.PSObject.Properties['Value']) {
                    throw [System.IO.InvalidDataException]::new("Operacion sin Value en $($action.Id): $($operation.Path)")
                }
            }
        }
        elseif ($action.Kind -eq 'Packages') {
            if (@($action.PackagePatterns).Count -eq 0) {
                throw [System.IO.InvalidDataException]::new("La accion $($action.Id) no contiene PackagePatterns.")
            }
            foreach ($pattern in @($action.PackagePatterns)) {
                Assert-RequiredString -Value $pattern -Field 'PackagePatterns' -Owner $action.Id
                if ($pattern -notmatch '^[A-Za-z0-9.*_-]+$') {
                    throw [System.IO.InvalidDataException]::new("Patron de paquete no valido en $($action.Id): $pattern")
                }
            }
        }
        elseif ($action.Kind -eq 'Special') {
            Assert-RequiredString -Value $action.Handler -Field 'Handler' -Owner $action.Id
            if ($action.Handler -notin $allowedHandlers) {
                throw [System.IO.InvalidDataException]::new("Handler no admitido en $($action.Id): $($action.Handler)")
            }
        }
    }

    $serviceIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($service in @($catalog.Services)) {
        foreach ($field in @('Id', 'Pattern', 'Title', 'Description', 'StartupType', 'Risk')) {
            Assert-RequiredString -Value $service.$field -Field $field -Owner 'Service'
        }
        if (-not $serviceIds.Add([string]$service.Id)) {
            throw [System.IO.InvalidDataException]::new("Id de servicio duplicado: $($service.Id)")
        }
        if ($service.Pattern -notmatch '^[A-Za-z0-9._*-]+$') {
            throw [System.IO.InvalidDataException]::new("Patron de servicio no valido: $($service.Pattern)")
        }
        if ($service.StartupType -notin @('Automatic', 'Manual', 'Disabled')) {
            throw [System.IO.InvalidDataException]::new("StartupType no valido en $($service.Id): $($service.StartupType)")
        }
        if ($service.Risk -notin $allowedRisks) {
            throw [System.IO.InvalidDataException]::new("Risk no admitido en $($service.Id): $($service.Risk)")
        }
        if ('TemplateName' -in $service.PSObject.Properties.Name) {
            Assert-RequiredString -Value $service.TemplateName -Field 'TemplateName' -Owner $service.Id
            if ($service.TemplateName -notmatch '^[A-Za-z0-9._-]+$' -or $service.Pattern -ne "$($service.TemplateName)_*") {
                throw [System.IO.InvalidDataException]::new("Plantilla de servicio no valida en $($service.Id): $($service.TemplateName)")
            }
        }
    }

    $profileIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($profile in @($catalog.Profiles)) {
        Assert-RequiredString -Value $profile.Id -Field 'Id' -Owner 'Profile'
        Assert-RequiredString -Value $profile.Title -Field 'Title' -Owner $profile.Id
        if (-not $profileIds.Add([string]$profile.Id)) {
            throw [System.IO.InvalidDataException]::new("Id de perfil duplicado: $($profile.Id)")
        }
        foreach ($id in @($profile.ActionIds)) {
            if (-not $actionIds.Contains([string]$id)) {
                throw [System.IO.InvalidDataException]::new("El perfil $($profile.Id) referencia una accion inexistente: $id")
            }
        }
        foreach ($id in @($profile.ServiceIds)) {
            if (-not $serviceIds.Contains([string]$id)) {
                throw [System.IO.InvalidDataException]::new("El perfil $($profile.Id) referencia un servicio inexistente: $id")
            }
            $entry = @($catalog.Services | Where-Object Id -eq $id)
            if ($entry.Count -ne 1 -or [bool]$entry[0].Protected) {
                throw [System.IO.InvalidDataException]::new("El perfil $($profile.Id) intenta incluir un servicio protegido: $id")
            }
        }
    }

    foreach ($tool in @($catalog.Tools)) {
        Assert-RequiredString -Value $tool.Id -Field 'Id' -Owner 'Tool'
        Assert-RequiredString -Value $tool.Title -Field 'Title' -Owner $tool.Id
        Assert-RequiredString -Value $tool.Url -Field 'Url' -Owner $tool.Id
        $uri = [Uri]$tool.Url
        if ($uri.Scheme -ne 'https') {
            throw [System.IO.InvalidDataException]::new("La herramienta $($tool.Id) no usa HTTPS: $($tool.Url)")
        }
    }

    return $catalog
}

Export-ModuleMember -Function Import-DebloatCatalog
