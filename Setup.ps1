[CmdletBinding()]
param(
    [switch]$SkipApps,
    [switch]$SkipCleanup,
    [switch]$SkipConfigs,
    [switch]$SkipFinalize,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = $PSScriptRoot
Import-Module (Join-Path $repoRoot 'modules/SetupHelpers.psm1') -Force

Write-SetupStep "Starting Windows setup from $repoRoot"
if ($DryRun) {
    Write-SetupWarning 'Dry run mode enabled: no packages will be installed.'
}

if (-not $SkipApps) {
    & (Join-Path $repoRoot 'scripts/Install-Apps.ps1') -RepositoryRoot $repoRoot -DryRun:$DryRun
}

if (-not $SkipCleanup) {
    & (Join-Path $repoRoot 'scripts/Remove-DeprecatedApps.ps1') -RepositoryRoot $repoRoot -DryRun:$DryRun
}

if (-not $SkipConfigs) {
    & (Join-Path $repoRoot 'scripts/Import-Configs.ps1') -RepositoryRoot $repoRoot
}

if (-not $SkipFinalize) {
    & (Join-Path $repoRoot 'scripts/Finalize.ps1') -RepositoryRoot $repoRoot
}

Write-SetupSuccess 'Setup completed.'
