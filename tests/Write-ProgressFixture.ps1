[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$OutputBasePath,
    [Parameter(Mandatory)]
    [int]$Iterations
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Common.psm1')
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Catalog.psm1')
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Engine.psm1')
$sessionPath = "$OutputBasePath.session"
$context = New-DebloatContext -SessionPath $sessionPath
Write-DebloatLog -Context $context -Level Info -Component 'Fixture' -Message 'Live log integration started.' -Data @{ Iterations = $Iterations }
for ($index = 1; $index -le $Iterations; $index++) {
    if ($index % 25 -eq 0) {
        Write-DebloatLog -Context $context -Level Info -Component 'Fixture' -Message 'Live fixture step.' -Data @{ Current = $index; Total = $Iterations }
    }
    Save-DebloatJson -Path "$OutputBasePath.progress.json" -InputObject ([pscustomobject]@{
        Message = 'Concurrent IPC integration test'
        Current = $index
        Total = $Iterations
        SessionPath = $sessionPath
    })
    Start-Sleep -Milliseconds 2
}
Save-DebloatJson -Path "$OutputBasePath.result.json" -InputObject ([pscustomobject]@{
    Success = $true
    SessionPath = $sessionPath
    WarningCount = 0
    Message = 'IPC integration completed without system changes.'
})
