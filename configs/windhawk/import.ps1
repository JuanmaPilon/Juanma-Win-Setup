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

    if (-not (Test-Path (Join-Path $env:ProgramFiles 'Windhawk\windhawk.ini'))) {
        Write-SetupError 'Windhawk is not installed in Program Files, but the backup is registry-mode.'
        Write-SetupWarning 'Install Windhawk first (winget install RamenSoftware.Windhawk), open it once, then re-run this import.'
        return
    }

    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

    $hklmReg = Join-Path $dataSourceRoot 'windhawk-hklm.reg'
    $hkcuReg = Join-Path $dataSourceRoot 'windhawk-hkcu.reg'
    $sourcesRoot = Join-Path $dataSourceRoot 'ModsSource'
    $engineDataRoot = Join-Path $dataSourceRoot 'Engine'
    $profileSource = Join-Path $dataSourceRoot 'userprofile.json'
    $manifestPath = Join-Path $dataSourceRoot 'mods-manifest.json'
    $programDataRoot = Join-Path $env:ProgramData 'Windhawk'

    if ($DryRun) {
        Write-SetupWarning 'Dry run mode enabled: no Windhawk changes will be applied.'
        if (Test-Path $hklmReg) { Write-SetupInfo "[DryRun] Would import registry: $hklmReg" }
        if (Test-Path $hkcuReg) { Write-SetupInfo "[DryRun] Would import registry: $hkcuReg" }
        if (Test-Path $sourcesRoot) { Write-SetupInfo "[DryRun] Would restore $((@(Get-ChildItem $sourcesRoot -File)).Count) mod source file(s) to $programDataRoot\ModsSource" }
        if (Test-Path (Join-Path $engineDataRoot 'Mods')) { Write-SetupInfo "[DryRun] Would restore $((@(Get-ChildItem (Join-Path $engineDataRoot 'Mods') -Recurse -File -Filter '*.dll')).Count) compiled mod binary(ies) to $programDataRoot\Engine\Mods" }
        if (Test-Path (Join-Path $engineDataRoot 'ModsWritable')) { Write-SetupInfo "[DryRun] Would restore Windhawk per-mod storage." }
        if (Test-Path $profileSource) { Write-SetupInfo '[DryRun] Would restore Windhawk user profile.' }
        Write-SetupInfo '[DryRun] Would stop the Windhawk UI + service, then restart the service.'
        if (-not $isAdmin) { Write-SetupWarning '[DryRun] A real run needs an elevated session (administrator).' }
        Write-SetupSuccess 'Dry run completed.'
        return
    }

    if (-not $isAdmin) {
        Write-SetupError 'Windhawk registry import needs an elevated session (writes HKLM and ProgramData, restarts a service).'
        Write-SetupWarning 'Close this window and run Menu.cmd (or PowerShell) as administrator, then import configs again.'
        return
    }

    if (-not (Get-Service -Name 'Windhawk' -ErrorAction SilentlyContinue)) {
        Write-SetupError 'The Windhawk service is not installed. Install Windhawk first and run its UI once, then re-run this import.'
        return
    }

    # Stop the engine AND the UI: the UI caches installed mods in memory and rewrites
    # userprofile.json when it exits, which silently undoes this import.
    Write-SetupInfo 'Stopping Windhawk (UI + service) before restoring mods...'
    Get-Process -Name 'windhawk' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    try {
        Stop-Service -Name 'Windhawk' -Force -ErrorAction Stop
        Start-Sleep -Milliseconds 800
        Write-SetupInfo 'Windhawk stopped.'
    }
    catch {
        Write-SetupWarning "Could not stop the Windhawk service: $($_.Exception.Message)"
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

    # Compiled mod DLLs: the registry points at these by LibraryFileName, so a mod
    # without its binary shows up as "not installed" in the Windhawk UI.
    $compiledRoot = Join-Path $engineDataRoot 'Mods'
    if (Test-Path $compiledRoot) {
        foreach ($archDir in Get-ChildItem $compiledRoot -Directory -ErrorAction SilentlyContinue) {
            $targetArchDir = Join-Path (Join-Path $programDataRoot 'Engine/Mods') $archDir.Name
            if (-not (Test-Path $targetArchDir)) { New-Item -ItemType Directory -Path $targetArchDir -Force | Out-Null }
            foreach ($dll in Get-ChildItem $archDir.FullName -File -Filter '*.dll' -ErrorAction SilentlyContinue) {
                Copy-Item $dll.FullName -Destination (Join-Path $targetArchDir $dll.Name) -Force
                Write-SetupInfo "Restored compiled mod: Engine/Mods/$($archDir.Name)/$($dll.Name)"
            }
        }
    }
    else {
        Write-SetupWarning 'No compiled mod binaries in the backup. Mods will only appear after Windhawk recompiles them (needs network access).'
    }

    $writableSource = Join-Path $engineDataRoot 'ModsWritable'
    if (Test-Path $writableSource) {
        foreach ($writableFile in Get-ChildItem $writableSource -Recurse -File -ErrorAction SilentlyContinue) {
            $relativeWritable = $writableFile.FullName.Substring($writableSource.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
            $writableTargetPath = Join-Path (Join-Path $programDataRoot 'Engine/ModsWritable') $relativeWritable
            $writableTargetDir = Split-Path -Parent $writableTargetPath
            if (-not (Test-Path $writableTargetDir)) { New-Item -ItemType Directory -Path $writableTargetDir -Force | Out-Null }
            Copy-Item $writableFile.FullName -Destination $writableTargetPath -Force
        }
        Write-SetupInfo 'Restored Windhawk per-mod storage.'
    }

    if (Test-Path $profileSource) {
        Copy-Item $profileSource -Destination (Join-Path $programDataRoot 'userprofile.json') -Force
        Write-SetupInfo 'Restored Windhawk user profile.'
    }

    try {
        Start-Service -Name 'Windhawk' -ErrorAction Stop
        Write-SetupSuccess 'Windhawk service started.'
    }
    catch {
        Write-SetupWarning "Could not start the Windhawk service: $($_.Exception.Message)"
    }

    # Verification: registry entry + compiled binary + profile entry must all agree.
    $modsKey = 'HKLM:\SOFTWARE\Windhawk\Engine\Mods'
    $profileModIds = @()
    $profileFile = Join-Path $programDataRoot 'userprofile.json'
    if (Test-Path $profileFile) {
        try {
            $profileJson = Get-Content $profileFile -Raw | ConvertFrom-Json
            if ($profileJson.PSObject.Properties.Name -contains 'mods' -and $profileJson.mods) {
                $profileModIds = @($profileJson.mods.PSObject.Properties.Name)
            }
        }
        catch {
            Write-SetupWarning "Could not parse Windhawk user profile: $($_.Exception.Message)"
        }
    }

    $registeredMods = @()
    if (Test-Path $modsKey) {
        $registeredMods = @(Get-ChildItem $modsKey -ErrorAction SilentlyContinue | Select-Object -ExpandProperty PSChildName)
    }

    Write-SetupInfo 'Windhawk mod verification:'
    $brokenMods = 0
    foreach ($modId in $registeredMods) {
        $modProps = Get-ItemProperty (Join-Path $modsKey $modId) -ErrorAction SilentlyContinue
        $lib = if ($modProps -and $modProps.PSObject.Properties.Name -contains 'LibraryFileName') { $modProps.LibraryFileName } else { $null }
        $dllOk = $false
        if ($lib) {
            foreach ($arch in @('64', '32')) {
                if (Test-Path (Join-Path $programDataRoot "Engine/Mods/$arch/$lib")) { $dllOk = $true; break }
            }
        }
        $inProfile = $profileModIds -contains $modId
        if (-not $dllOk -or -not $inProfile) { $brokenMods++ }
        $state = if ($dllOk -and $inProfile) { 'OK  ' } else { 'FAIL' }
        Write-SetupInfo "  [$state] $modId (dll: $(if ($dllOk) { 'yes' } else { 'NO' }), profile: $(if ($inProfile) { 'yes' } else { 'NO' }))"
    }

    if ($registeredMods.Count -eq 0) {
        Write-SetupError 'No Windhawk mods were registered. The registry backup may be empty or the import was blocked.'
    }
    elseif ($brokenMods -gt 0) {
        Write-SetupWarning "$brokenMods mod(s) are incomplete. Open Windhawk and reinstall the affected mods from the catalog."
    }
    else {
        Write-SetupSuccess "All $($registeredMods.Count) Windhawk mod(s) restored with their compiled binaries."
    }

    Write-SetupInfo 'Open the Windhawk UI from the Start Menu to see the restored mods.'
    Write-SetupSuccess 'Windhawk configuration import completed (registry mode).'
    return
}

if ($DryRun) {
    Write-SetupWarning 'Dry run mode enabled: no Windhawk files will be modified.'
}

$iniPath = Join-Path $InstallPath 'windhawk.ini'
if (-not (Test-Path $iniPath)) {
    Write-SetupWarning "Windhawk portable install not found at $InstallPath. Install it first (windhawk_setup.exe /S /PORTABLE /D=<path>) and re-run this import."
    return
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
