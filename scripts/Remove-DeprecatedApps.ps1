[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Import-Module (Join-Path $RepositoryRoot 'modules/SetupHelpers.psm1') -Force

Write-SetupStep 'Checking for deprecated applications'

$manifestPath = Join-Path $RepositoryRoot 'apps/winget-remove.txt'
if (-not (Test-Path $manifestPath)) {
    Write-SetupInfo 'No apps/winget-remove.txt found; skipping cleanup stage.'
    return
}

$packages = @(Get-Content $manifestPath | Where-Object { $_ -and -not $_.TrimStart().StartsWith('#') } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

if ($packages.Count -eq 0) {
    Write-SetupInfo 'Deprecated apps list is empty; nothing to remove.'
    return
}

try {
    $wingetPath = Initialize-Winget
}
catch {
    Write-SetupWarning "Winget is not available; cannot check deprecated apps. $($_.Exception.Message)"
    return
}

$summary = [ordered]@{
    Removed = @()
    WouldRemove = @()
    Failed = @()
    NotPresent = @()
}

$total = $packages.Count
$index = 0

foreach ($packageId in $packages) {
    $index++
    Write-SetupProgress -Activity 'Removing deprecated applications' -Status "$packageId ($index/$total)" -PercentComplete ([int](($index - 1) * 100 / [Math]::Max($total, 1)))

    $listOutput = winget list --id $packageId --exact --source winget 2>$null
    $isInstalled = ($LASTEXITCODE -eq 0 -and $listOutput -match [regex]::Escape($packageId))

    if (-not $isInstalled) {
        Write-SetupInfo "Not installed, nothing to do: $packageId"
        $summary.NotPresent += $packageId
        continue
    }

    if ($DryRun) {
        Write-SetupWarning "Would uninstall deprecated package: $packageId"
        $summary.WouldRemove += $packageId
        continue
    }

    Write-SetupStep "Uninstalling deprecated package: $packageId"
    $uninstallOutput = winget uninstall --id $packageId --exact --silent --accept-source-agreements 2>&1
    $uninstallText = ($uninstallOutput | Out-String)

    if ($LASTEXITCODE -eq 0) {
        Write-SetupSuccess "Removed deprecated package: $packageId"
        $summary.Removed += $packageId
    }
    else {
        Write-SetupWarning "Failed to uninstall '$packageId' (it may be a per-user MSI or need manual attention)."
        Write-SetupWarning $uninstallText.Trim()
        $summary.Failed += $packageId
    }
}

Clear-SetupProgress

Write-SetupStep "Cleanup summary: removed $($summary.Removed.Count); would remove $($summary.WouldRemove.Count); not present $($summary.NotPresent.Count); failed $($summary.Failed.Count)"

if ($summary.Removed.Count -gt 0) {
    Write-SetupInfo "Removed during this run: $($summary.Removed -join ', ')"
}
if ($summary.WouldRemove.Count -gt 0) {
    Write-SetupInfo "Would remove in dry-run: $($summary.WouldRemove -join ', ')"
}
if ($summary.Failed.Count -gt 0) {
    Write-SetupWarning "Manual attention needed: $($summary.Failed -join ', ')"
    Write-SetupWarning 'Some MSI-based apps fail to uninstall via winget. Remove them from Settings > Apps or with their own uninstaller.'
}

Write-SetupStep 'Cleanup stage completed.'
