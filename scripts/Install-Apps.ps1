[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $RepositoryRoot 'modules/SetupHelpers.psm1') -Force

if ($DryRun) {
    Write-SetupStep 'Running application installation in dry-run mode.'
}

Write-SetupStep 'Ensuring applications from Winget manifest are present'
$wingetAvailable = $false

try {
    $wingetPath = Initialize-Winget
    $wingetAvailable = $true
    Write-SetupSuccess "Winget ready at $wingetPath"
}
catch {
    Write-SetupError 'Winget is not available after bootstrap attempts.'
    Write-SetupWarning 'This commonly happens on LTSC/IoT builds or systems without App Installer.'
    Write-SetupWarning $_.Exception.Message
    Write-SetupWarning 'Skipping package installation for this run.'
    Write-SetupWarning 'Install Winget manually and rerun the setup later.'
    return
}

$manifestPath = Join-Path $RepositoryRoot 'apps/winget-apps.txt'
if (-not (Test-Path $manifestPath)) {
    throw "Winget manifest not found at $manifestPath"
}

$packages = Get-Content $manifestPath | Where-Object { $_ -and -not $_.TrimStart().StartsWith('#') }
$defaultInstallLocation = if ($env:ProgramFiles) { $env:ProgramFiles } else { 'C:\Program Files' }

$summary = [ordered]@{
    Installed = @()
    WouldInstall = @()
    Failed = @()
}

$packageList = @($packages)
$packageTotal = [Math]::Max($packageList.Count, 1)
$packageIndex = 0

foreach ($package in $packageList) {
    $packageId = $package.Trim()
    if (-not $packageId) {
        continue
    }

    $packageIndex++
    Write-SetupProgress -Activity 'Installing applications' -Status "$packageId ($packageIndex/$packageTotal)" -PercentComplete ([int](($packageIndex - 1) * 100 / $packageTotal))
    Write-SetupStep "Checking package: $packageId"

    $listOutput = winget list --id $packageId --exact --source winget 2>$null
    if ($LASTEXITCODE -eq 0 -and $listOutput -match [regex]::Escape($packageId)) {
        Write-SetupStep "Package already installed; checking for updates: $packageId"

        $upgradeOutput = winget upgrade --id $packageId --source winget --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1
        $upgradeText = ($upgradeOutput | Out-String)

        if ($LASTEXITCODE -eq 0) {
            Write-SetupStep "Package already installed and upgrade check completed: $packageId"
            continue
        }

        if ($upgradeText -match 'No applicable update found|No upgrade available|No update available') {
            Write-SetupStep "Package already installed and up to date: $packageId"
            continue
        }

        Write-SetupStep "Package already installed; upgrade check did not return a usable result: $packageId"
        continue
    }

    $installArgs = @('install', '--id', $packageId, '--source', 'winget', '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity')
    $installOutput = & winget @installArgs 2>&1
    $installText = ($installOutput | Out-String)
    $installExitCode = $LASTEXITCODE

    if ($DryRun) {
        Write-SetupWarning "Would install package: $packageId"
        $summary.WouldInstall += $packageId
        continue
    }

    if ($installExitCode -ne 0 -and $installText -match 'requires an install location|Install location is required') {
        Write-SetupStep "Package requires an install location; retrying with: $defaultInstallLocation"
        $installArgs += @('--location', $defaultInstallLocation)
        $installOutput = & winget @installArgs 2>&1
        $installText = ($installOutput | Out-String)
        $installExitCode = $LASTEXITCODE
    }

    if ($installExitCode -ne 0) {
        Write-SetupError "Failed to install package: $packageId"
        Write-SetupWarning $installText
        Write-SetupWarning "Continuing with the next package."
        $summary.Failed += $packageId
        continue
    }

    Write-SetupSuccess "Installed package: $packageId"
    $summary.Installed += $packageId
}

Write-SetupStep 'Application installation stage completed.'

Clear-SetupProgress

$summaryText = "Installed: $($summary.Installed.Count); Would install: $($summary.WouldInstall.Count); Failed: $($summary.Failed.Count)"
Write-SetupStep "Install summary: $summaryText"

if ($summary.Installed.Count -gt 0) {
    Write-SetupStep "Installed during this run: $($summary.Installed -join ', ')"
}

if ($summary.WouldInstall.Count -gt 0) {
    Write-SetupStep "Would install in dry-run: $($summary.WouldInstall -join ', ')"
}

if ($summary.Failed.Count -gt 0) {
    Write-SetupStep "Failed packages: $($summary.Failed -join ', ')"
}

Write-SetupStep 'Application installation stage completed.'
