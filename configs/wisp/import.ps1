[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Import-Module (Join-Path $RepositoryRoot 'modules/SetupHelpers.psm1') -Force

Write-SetupStep 'Preparing Wisp configuration import'

$privateSourceRoot = Join-Path $RepositoryRoot 'private-configs/wisp'
$publicSourceRoot = Join-Path $RepositoryRoot 'configs/wisp'
$sourceRoot = if (Test-Path $privateSourceRoot) { $privateSourceRoot } else { $publicSourceRoot }
$sourceRoot = [System.IO.Path]::GetFullPath($sourceRoot)

if (-not (Test-Path $sourceRoot)) {
    Write-SetupWarning 'Wisp config source directory not found.'
    return
}

$configSource = Join-Path $sourceRoot 'config.toml'
if (-not (Test-Path $configSource)) {
    Write-SetupWarning "Wisp config.toml not found in $sourceRoot. Export it first from the machine you are copying."
    return
}

$targetRoot = Join-Path $env:APPDATA 'wisp'
$metaPath = Join-Path $sourceRoot '_install.txt'

if (Test-Path $metaPath) {
    $meta = @{}
    foreach ($line in Get-Content $metaPath) {
        if ($line -match '^\s*([^=]+)=(.*)$') { $meta[$Matches[1].Trim()] = $Matches[2].Trim() }
    }
    if ($meta.ContainsKey('version')) { Write-SetupInfo "Backup exported from Wisp $($meta['version'])." }
    if ($meta.ContainsKey('exe') -and $meta['exe'] -notlike '*\Programs\Wisp\*' -and $meta['exe'] -ne 'not-found') {
        Write-SetupWarning "The source machine ran Wisp from $($meta['exe']). Install it in %LOCALAPPDATA%\Programs\Wisp on this machine."
    }
}

$wispExe = Join-Path $env:LOCALAPPDATA 'Programs\Wisp\wisp.exe'
if (-not (Test-Path $wispExe)) {
    Write-SetupWarning "Wisp is not installed at $wispExe."
    Write-SetupWarning 'Wisp has no Winget package yet: download the release zip and extract it there (see configs/manual-installs/README.md).'
    Write-SetupWarning 'The configuration will still be restored so Wisp picks it up on first run.'
}

$filesToCopy = @()
$filesToCopy += [pscustomobject]@{ Source = $configSource; Relative = 'config.toml' }

$surfacesSource = Join-Path $sourceRoot 'surfaces'
if (Test-Path $surfacesSource) {
    foreach ($surfaceFile in Get-ChildItem $surfacesSource -File -Filter '*.toml' -ErrorAction SilentlyContinue) {
        $filesToCopy += [pscustomobject]@{ Source = $surfaceFile.FullName; Relative = "surfaces/$($surfaceFile.Name)" }
    }
}

if ($DryRun) {
    Write-SetupWarning 'Dry run mode enabled: no Wisp files will be modified.'
    foreach ($file in $filesToCopy) {
        Write-SetupInfo "[DryRun] Would import Wisp file: $($file.Relative) -> $targetRoot"
    }
    Write-SetupWarning '[DryRun] Would stop and restart the running Wisp process (the config is read when the launcher opens).'
    Write-SetupSuccess 'Dry run completed.'
    return
}

# Wisp reads config.toml when the launcher opens, so a running instance would keep
# using the old settings until restarted; stop it, restore, then start it again.
$wispProcesses = @(Get-Process -Name 'wisp' -ErrorAction SilentlyContinue)
$wasRunning = $wispProcesses.Count -gt 0
if ($wasRunning) {
    Write-SetupInfo 'Stopping Wisp before restoring its configuration...'
    $wispProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 600
}

$imported = 0
foreach ($file in $filesToCopy) {
    $destinationPath = Join-Path $targetRoot $file.Relative
    $destinationDirectory = Split-Path -Parent $destinationPath

    try {
        if (-not (Test-Path $destinationDirectory)) {
            New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
        }

        if (Test-Path $destinationPath) {
            $backupPath = "$destinationPath.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
            Copy-Item -Path $destinationPath -Destination $backupPath -Force
        }

        Copy-Item -Path $file.Source -Destination $destinationPath -Force
        Write-SetupInfo "Imported Wisp file: $($file.Relative)"
        $imported++
    }
    catch {
        Write-SetupWarning "Failed to import Wisp file '$($file.Relative)': $($_.Exception.Message)"
    }
}

if ($wasRunning) {
    if (Test-Path $wispExe) {
        try {
            Start-Process -FilePath $wispExe -ErrorAction Stop | Out-Null
            Write-SetupSuccess 'Wisp restarted with the restored configuration.'
        }
        catch {
            Write-SetupWarning "Could not restart Wisp: $($_.Exception.Message). Start it from the Start Menu."
        }
    }
    else {
        Write-SetupWarning 'Start Wisp manually so the restored configuration takes effect.'
    }
}
else {
    Write-SetupWarning 'Start Wisp so the restored configuration takes effect.'
}

Write-SetupSuccess "Wisp configuration import completed ($imported files)."
