[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [switch]$DryRun,
    [string]$InstallPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Import-Module (Join-Path $RepositoryRoot 'modules/SetupHelpers.psm1') -Force

Write-SetupStep 'Preparing Windhawk configuration import'

$privateSourceRoot = Join-Path $RepositoryRoot 'private-configs/windhawk'
$publicSourceRoot = Join-Path $RepositoryRoot 'configs/windhawk'
$sourceRoot = if (Test-Path $privateSourceRoot) { $privateSourceRoot } else { $publicSourceRoot }
$sourceRoot = [System.IO.Path]::GetFullPath($sourceRoot)

if (-not (Test-Path $sourceRoot)) {
    Write-SetupWarning 'Windhawk config source directory not found.'
    return
}

if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    $InstallPath = Join-Path $env:LOCALAPPDATA 'Programs\Windhawk'
}

$iniPath = Join-Path $InstallPath 'windhawk.ini'
if (-not (Test-Path $iniPath)) {
    Write-SetupWarning "Windhawk portable install not found at $InstallPath. Install it first (windhawk_setup.exe /S /PORTABLE /D=<path>) and re-run this import."
    return
}

$dataSourceRoot = Join-Path $sourceRoot 'data'
if (-not (Test-Path $dataSourceRoot)) {
    Write-SetupWarning 'No Windhawk data backup found (data/ folder missing).'
    return
}

if ($DryRun) {
    Write-SetupWarning 'Dry run mode enabled: no Windhawk files will be modified.'
}

$dataTargetRoot = Join-Path $InstallPath 'AppData'

# Stop Windhawk so the settings are not overwritten by a running instance
if (-not $DryRun) {
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -like 'windhawk*' } |
        Stop-Process -Force -ErrorAction SilentlyContinue
}

$imported = 0
$files = Get-ChildItem -Path $dataSourceRoot -Recurse -File -ErrorAction SilentlyContinue
foreach ($file in $files) {
    $relativePath = $file.FullName.Substring($dataSourceRoot.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $destinationPath = Join-Path $dataTargetRoot $relativePath
    $destinationDirectory = Split-Path -Parent $destinationPath

    if ($DryRun) {
        Write-SetupInfo "[DryRun] Would import Windhawk file: $relativePath"
        $imported++
        continue
    }

    try {
        if (-not (Test-Path $destinationDirectory)) {
            New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
        }

        if (Test-Path $destinationPath) {
            $backupPath = "$destinationPath.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
            Copy-Item -Path $destinationPath -Destination $backupPath -Force
        }

        Copy-Item -Path $file.FullName -Destination $destinationPath -Force
        Write-SetupInfo "Imported Windhawk file: $relativePath"
        $imported++
    }
    catch {
        Write-SetupWarning "Failed to import Windhawk file '$relativePath': $($_.Exception.Message)"
    }
}

if (-not $DryRun) {
    Write-SetupWarning 'Start Windhawk again so the restored mods and settings take effect. Mods may need a moment to recompile.'
}

Write-SetupSuccess "Windhawk configuration import completed ($imported files)."
