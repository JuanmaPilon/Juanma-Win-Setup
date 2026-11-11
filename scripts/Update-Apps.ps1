[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Import-Module (Join-Path $RepositoryRoot 'modules/SetupHelpers.psm1') -Force

Write-SetupStep 'Updating all installed applications with Winget'

try {
    $wingetPath = Initialize-Winget
    Write-SetupInfo "Winget: $wingetPath"
}
catch {
    Write-SetupError 'Winget is not available.'
    Write-SetupWarning $_.Exception.Message
    return
}

if ($DryRun) {
    Write-SetupWarning 'Dry run mode: listing upgradable packages only.'
    Write-SetupProgress -Activity 'Checking upgrades' -Status 'Querying winget...'
    $listOutput = winget upgrade --source winget --accept-source-agreements 2>&1
    Clear-SetupProgress
    $listOutput | Out-String | Write-Host
    Write-SetupSuccess 'Dry run completed (nothing was updated).'
    return
}

Write-SetupProgress -Activity 'Updating applications' -Status 'Running winget upgrade --all...'
$upgradeOutput = winget upgrade --all --source winget --include-unknown --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1
$upgradeExitCode = $LASTEXITCODE
Clear-SetupProgress

$upgradeText = ($upgradeOutput | Out-String)

# Always show the tail so the user can see what happened without scrolling noise
$tail = ($upgradeOutput | Select-Object -Last 15)
$tail | ForEach-Object { Write-Host $_ }

if ($upgradeExitCode -eq 0) {
    Write-SetupSuccess 'All upgradable applications were updated.'
}
elseif ($upgradeText -match 'No installed package found matching input criteria|No applicable upgrade|No available upgrade') {
    Write-SetupSuccess 'Everything is already up to date.'
}
else {
    Write-SetupWarning "winget upgrade exited with code $upgradeExitCode. Some packages may need manual updates."
}

Write-SetupWarning 'Tip: some apps hold recovery files or need a reboot to finish updating.'
Write-SetupStep 'Update stage completed.'
