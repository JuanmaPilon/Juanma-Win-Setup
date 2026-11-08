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

# Mode: registry (normal install) or portable
$modeFile = Join-Path $dataSourceRoot 'mode.txt'
$mode = if (Test-Path $modeFile) { (Get-Content $modeFile -Raw).Trim() }
        elseif (Test-Path (Join-Path $dataSourceRoot 'windhawk-hklm.reg')) { 'registry' }
        else { 'portable' }

if ($mode -eq 'registry') {
    Write-SetupInfo 'Windhawk backup mode: registry (normal install)'

    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

    $hklmReg = Join-Path $dataSourceRoot 'windhawk-hklm.reg'
    $hkcuReg = Join-Path $dataSourceRoot 'windhawk-hkcu.reg'
    $sourcesRoot = Join-Path $dataSourceRoot 'ModsSource'
    $programDataRoot = Join-Path $env:ProgramData 'Windhawk'

    if ($DryRun) {
        Write-SetupWarning 'Dry run mode enabled: no Windhawk changes will be applied.'
        if (Test-Path $hklmReg) { Write-SetupInfo "[DryRun] Would import registry: $hklmReg" }
        if (Test-Path $hkcuReg) { Write-SetupInfo "[DryRun] Would import registry: $hkcuReg" }
        if (Test-Path $sourcesRoot) { Write-SetupInfo "[DryRun] Would restore $((@(Get-ChildItem $sourcesRoot -File)).Count) mod source file(s) to $programDataRoot\ModsSource" }
        if (Test-Path (Join-Path $dataSourceRoot 'userprofile.json')) { Write-SetupInfo '[DryRun] Would restore Windhawk user profile.' }
        Write-SetupInfo '[DryRun] Would restart the Windhawk service.'
        Write-SetupSuccess 'Dry run completed.'
        return
    }

    if (-not $isAdmin) {
        Write-SetupWarning 'Windhawk registry import needs an elevated session (writes HKLM and ProgramData, restarts a service). Run the import again from an administrator PowerShell.'
        return
    }

    foreach ($regFile in @($hklmReg, $hkcuReg)) {
        if (-not (Test-Path $regFile)) { continue }
        try {
            reg import $regFile | Out-Null
            Write-SetupSuccess "Imported registry: $(Split-Path -Leaf $regFile)"
        }
        catch {
            Write-SetupWarning "Failed to import registry file '$regFile': $($_.Exception.Message)"
        }
    }

    if (Test-Path $sourcesRoot) {
        $targetSources = Join-Path $programDataRoot 'ModsSource'
        if (-not (Test-Path $targetSources)) { New-Item -ItemType Directory -Path $targetSources -Force | Out-Null }
        Get-ChildItem $sourcesRoot -File | ForEach-Object {
            Copy-Item $_.FullName -Destination (Join-Path $targetSources $_.Name) -Force
            Write-SetupInfo "Restored Windhawk mod source: $($_.Name)"
        }
    }

    $profileSource = Join-Path $dataSourceRoot 'userprofile.json'
    if (Test-Path $profileSource) {
        Copy-Item $profileSource -Destination (Join-Path $programDataRoot 'userprofile.json') -Force
        Write-SetupInfo 'Restored Windhawk user profile.'
    }

    try {
        Restart-Service -Name 'Windhawk' -Force -ErrorAction Stop
        Write-SetupSuccess 'Windhawk service restarted.'
    }
    catch {
        Write-SetupWarning "Could not restart the Windhawk service: $($_.Exception.Message)"
    }

    Write-SetupSuccess 'Windhawk configuration import completed (registry mode).'
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
