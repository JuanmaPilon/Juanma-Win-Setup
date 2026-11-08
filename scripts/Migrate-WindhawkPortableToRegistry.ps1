[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Import-Module (Join-Path $RepositoryRoot 'modules/SetupHelpers.psm1') -Force

Write-SetupStep 'Windhawk migration: portable INI settings -> registry (normal install)'

$iniRoot = Join-Path $RepositoryRoot 'private-configs/windhawk/data/Engine/Mods'
if (-not (Test-Path $iniRoot)) {
    $legacyRoot = Join-Path $RepositoryRoot 'private-configs/windhawk/portable-legacy/Engine/Mods'
    if (Test-Path $legacyRoot) {
        $iniRoot = $legacyRoot
    }
}

if (-not (Test-Path $iniRoot)) {
    Write-SetupWarning "Portable backup not found (checked data/Engine/Mods and portable-legacy/Engine/Mods). Nothing to migrate."
    return
}

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

if (-not $DryRun -and -not $isAdmin) {
    Write-SetupWarning 'This migration writes HKLM\SOFTWARE\Windhawk. Run it from an elevated PowerShell.'
    return
}

$iniFiles = Get-ChildItem $iniRoot -Filter '*.ini' -File -ErrorAction SilentlyContinue
if (-not $iniFiles) {
    Write-SetupWarning 'No mod INI files found in the backup.'
    return
}

$modBaseKey = 'HKLM:\SOFTWARE\Windhawk\Engine\Mods'
$programDataRoot = Join-Path $env:ProgramData 'Windhawk'
$portableAppData = Join-Path $env:LOCALAPPDATA 'Programs\Windhawk\AppData'

# Step 1: copy compiled mod DLLs and shared libraries from the portable install
$restoredBinaries = 0
if (Test-Path $portableAppData) {
    foreach ($arch in @('64', '32')) {
        $srcArch = Join-Path $portableAppData "Engine/Mods/$arch"
        if (-not (Test-Path $srcArch)) { continue }
        $dstArch = Join-Path $programDataRoot "Engine/Mods/$arch"
        foreach ($binary in Get-ChildItem $srcArch -File -ErrorAction SilentlyContinue) {
            if ($DryRun) {
                Write-SetupInfo "[DryRun] Would copy binary: $arch/$($binary.Name)"
                continue
            }
            if (-not (Test-Path $dstArch)) { New-Item -ItemType Directory -Path $dstArch -Force | Out-Null }
            Copy-Item $binary.FullName -Destination (Join-Path $dstArch $binary.Name) -Force
            $restoredBinaries++
        }
    }

    $srcSources = Join-Path $portableAppData 'ModsSource'
    if (Test-Path $srcSources) {
        $dstSources = Join-Path $programDataRoot 'ModsSource'
        foreach ($source in Get-ChildItem $srcSources -Filter '*.wh.cpp' -File -ErrorAction SilentlyContinue) {
            if ($DryRun) {
                Write-SetupInfo "[DryRun] Would copy source: $($source.Name)"
                continue
            }
            if (-not (Test-Path $dstSources)) { New-Item -ItemType Directory -Path $dstSources -Force | Out-Null }
            Copy-Item $source.FullName -Destination (Join-Path $dstSources $source.Name) -Force
            $restoredBinaries++
        }
    }

    if (-not $DryRun) { Write-SetupSuccess "Restored $restoredBinaries mod binary/source file(s) into ProgramData." }
}
else {
    Write-SetupWarning "Portable install not found at $portableAppData; only settings will be written (mods must be installed from the catalog)."
}

function Read-IniSection {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Section
    )

    $values = [ordered]@{}
    $current = ''
    foreach ($line in Get-Content -Path $Path -Encoding Unicode) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\[(.+)\]$') {
            $current = $Matches[1]
            continue
        }
        if ($current -ne $Section -or $trimmed -eq '' -or $trimmed -notmatch '=') { continue }
        $idx = $trimmed.IndexOf('=')
        $name = $trimmed.Substring(0, $idx)
        $value = $trimmed.Substring($idx + 1)
        $values[$name] = $value
    }

    return $values
}

$migrated = 0
$skipped = 0

foreach ($iniFile in $iniFiles) {
    $modId = $iniFile.BaseName

    $modSection = Read-IniSection -Path $iniFile.FullName -Section 'Mod'
    $settingsSection = Read-IniSection -Path $iniFile.FullName -Section 'Settings'

    $modKey = Join-Path $modBaseKey $modId
    $settingsKey = Join-Path $modKey 'Settings'

    foreach ($modSettingName in $modSection.Keys) {
        if ($modSettingName -eq 'SettingsChangeTime') { continue }
        if ($DryRun) {
            Write-SetupInfo "[DryRun] $modId\$modSettingName = $($modSection[$modSettingName])"
            continue
        }
        if (-not (Test-Path $modKey)) { New-Item -Path $modKey -Force | Out-Null }
        Set-ItemProperty -Path $modKey -Name $modSettingName -Value ([string]$modSection[$modSettingName]) -Type String
    }

    foreach ($settingName in $settingsSection.Keys) {
        if ($DryRun) {
            Write-SetupInfo "[DryRun] $modId\Settings\$settingName = $($settingsSection[$settingName])"
            continue
        }
        if (-not (Test-Path $settingsKey)) { New-Item -Path $settingsKey -Force | Out-Null }
        Set-ItemProperty -Path $settingsKey -Name $settingName -Value ([string]$settingsSection[$settingName]) -Type String
    }

    Write-SetupSuccess "Migrated settings for mod: $modId"
    $migrated++
}

if (-not $DryRun) {
    try {
        Restart-Service -Name 'Windhawk' -Force -ErrorAction Stop
        Write-SetupSuccess 'Windhawk service restarted.'
    }
    catch {
        Write-SetupWarning "Could not restart the Windhawk service: $($_.Exception.Message)"
    }
}

Write-SetupSuccess "Migration completed. Migrated: $migrated; skipped (mod not installed): $skipped."
