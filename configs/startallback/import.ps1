[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [switch]$RestoreShellState,
    [switch]$RestorePinnedApps,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

try {
    Import-Module (Join-Path $RepositoryRoot 'modules/SetupHelpers.psm1') -Force
}
catch {
    Write-Host "[error] Failed to import SetupHelpers module: $_" -ForegroundColor Red
    return
}

Write-SetupStep 'Preparing StartAllBack configuration import'

$privateSourceRoot = Join-Path $RepositoryRoot 'private-configs/startallback'
$publicSourceRoot = Join-Path $RepositoryRoot 'configs/startallback'
$sourceRoot = if (Test-Path $privateSourceRoot) { $privateSourceRoot } else { $publicSourceRoot }
$targetRoot = Join-Path $env:LOCALAPPDATA 'StartAllBack'

if (-not (Test-Path $sourceRoot)) {
    Write-SetupWarning 'StartAllBack config source directory not found.'
    return
}

if (-not (Test-Path $targetRoot)) {
    Write-SetupWarning 'StartAllBack target directory not found. Install StartAllBack first.'
    return
}

if ($DryRun) {
    Write-SetupWarning 'Dry run mode enabled: no StartAllBack changes will be applied.'
    foreach ($regName in @('StartIsBack-HKCU.reg', 'StartIsBack-HKLM.reg', 'Explorer-Advanced.reg', 'Explorer-StuckRects3.reg', 'Explorer-Taskband.reg')) {
        if (Test-Path (Join-Path $sourceRoot $regName)) { Write-SetupInfo "[DryRun] Would import registry file: $regName" }
    }
    $filesRoot = Join-Path $sourceRoot 'files'
    if (Test-Path $filesRoot) {
        $count = (Get-ChildItem $filesRoot -Recurse -File -ErrorAction SilentlyContinue).Count
        Write-SetupInfo "[DryRun] Would copy $count StartAllBack data files to $targetRoot"
    }
    Write-SetupSuccess 'Dry run completed.'
    return
}

$isAdmin = $false
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

$userRegPath = Join-Path $sourceRoot 'StartIsBack-HKCU.reg'
if (Test-Path $userRegPath) {
    try {
        reg import $userRegPath | Out-Null
        Write-SetupSuccess 'Imported StartAllBack user registry key.'
    }
    catch {
        Write-SetupWarning "Failed to import StartAllBack user registry key: $($_.Exception.Message)"
    }
}

$machineRegPath = Join-Path $sourceRoot 'StartIsBack-HKLM.reg'
if (Test-Path $machineRegPath) {
    if ($isAdmin) {
        try {
            reg import $machineRegPath | Out-Null
            Write-SetupSuccess 'Imported StartAllBack machine registry key.'
        }
        catch {
            Write-SetupWarning "Failed to import StartAllBack machine registry key: $($_.Exception.Message)"
        }
    }
    else {
        Write-SetupWarning 'Skipping StartAllBack machine registry import (requires administrator session).'
    }
}

if ($RestoreShellState) {
    $shellRegFiles = @('Explorer-Advanced.reg', 'Explorer-StuckRects3.reg')
    foreach ($regFile in $shellRegFiles) {
        $regPath = Join-Path $sourceRoot $regFile
        if (Test-Path $regPath) {
            try {
                reg import $regPath | Out-Null
                Write-SetupSuccess "Imported shell state key: $regFile"
            }
            catch {
                Write-SetupWarning "Failed to import shell state key '$regFile': $($_.Exception.Message)"
            }
        }
    }
}

if ($RestorePinnedApps) {
    $taskbandRegPath = Join-Path $sourceRoot 'Explorer-Taskband.reg'
    if (Test-Path $taskbandRegPath) {
        try {
            reg import $taskbandRegPath | Out-Null
            Write-SetupSuccess 'Imported taskbar pinned apps key.'
        }
        catch {
            Write-SetupWarning "Failed to import taskbar pinned apps key: $($_.Exception.Message)"
        }
    }
}

$filesSourceRoot = Join-Path $sourceRoot 'files'
if (-not (Test-Path $filesSourceRoot)) {
    $filesSourceRoot = $sourceRoot
}

$filesToCopy = Get-ChildItem -Path $filesSourceRoot -Recurse -File -ErrorAction SilentlyContinue

foreach ($sourceFile in $filesToCopy) {
    $relativePath = $sourceFile.FullName.Substring($filesSourceRoot.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $destinationPath = Join-Path $targetRoot $relativePath
    $destinationDirectory = Split-Path -Parent $destinationPath

    try {
        if (-not (Test-Path $destinationDirectory)) {
            New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
        }

        Copy-Item -Path $sourceFile.FullName -Destination $destinationPath -Force
        Write-SetupInfo "Imported StartAllBack file: $relativePath"
    }
    catch {
        Write-SetupWarning "Failed to import StartAllBack file '$relativePath': $($_.Exception.Message)"
    }
}

try {
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Process explorer.exe | Out-Null
    Write-SetupSuccess 'Restarted Explorer to apply StartAllBack settings.'
}
catch {
    Write-SetupWarning 'Could not restart Explorer automatically. Sign out and sign in again if changes are not visible.'
}

Write-SetupSuccess 'StartAllBack configuration import completed.'
