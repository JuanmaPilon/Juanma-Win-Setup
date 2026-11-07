[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Import-Module (Join-Path $RepositoryRoot 'modules/SetupHelpers.psm1') -Force

Write-SetupStep 'Preparing Git configuration import'

$privateSourceRoot = Join-Path $RepositoryRoot 'private-configs/git'
$publicSourceRoot = Join-Path $RepositoryRoot 'configs/git'
$sourceRoot = if (Test-Path $privateSourceRoot) { $privateSourceRoot } else { $publicSourceRoot }

if (-not (Test-Path $sourceRoot)) {
	Write-SetupWarning 'Git config source directory not found.'
	return
}

$gitTargets = @(
	@{ Source = 'home/.gitconfig'; Destination = Join-Path $HOME '.gitconfig' },
	@{ Source = 'home/.config/git/config'; Destination = Join-Path $HOME '.config/git/config' },
	@{ Source = 'home/.config/git/ignore'; Destination = Join-Path $HOME '.config/git/ignore' },
	@{ Source = 'home/.config/git/attributes'; Destination = Join-Path $HOME '.config/git/attributes' }
)

foreach ($target in $gitTargets) {
	$sourcePath = Join-Path $sourceRoot $target.Source
	if (-not (Test-Path $sourcePath)) {
		continue
	}

	if ($DryRun) {
		Write-SetupInfo "[DryRun] Would import Git file: $($target.Source)"
		continue
	}

	try {
		Copy-Item -Path $sourcePath -Destination $target.Destination -Force
		Write-SetupInfo "Imported Git file: $($target.Source)"
	}
	catch {
		Write-SetupWarning "Failed to import Git file '$($target.Source)': $($_.Exception.Message)"
	}
}

Write-SetupSuccess 'Git configuration import completed.'
