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
$installedMods = @(Get-ChildItem $modBaseKey -ErrorAction SilentlyContinue | Select-Object -ExpandProperty PSChildName)

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

    if ($installedMods -notcontains $modId) {
        Write-SetupWarning "Mod '$modId' is not installed in Windhawk yet. Install it from the catalog first, then re-run this migration."
        $skipped++
        continue
    }

    $modSection = Read-IniSection -Path $iniFile.FullName -Section 'Mod'
    $settingsSection = Read-IniSection -Path $iniFile.FullName -Section 'Settings'

    $modKey = Join-Path $modBaseKey $modId
    $settingsKey = Join-Path $modKey 'Settings'

    foreach ($operationalKey in @('Disabled', 'Include', 'Exclude')) {
        if (-not $modSection.Contains($operationalKey)) { continue }
        if ($DryRun) {
            Write-SetupInfo "[DryRun] $modId\$operationalKey = $($modSection[$operationalKey])"
            continue
        }
        if (-not (Test-Path $modKey)) { New-Item -Path $modKey -Force | Out-Null }
        Set-ItemProperty -Path $modKey -Name $operationalKey -Value ([string]$modSection[$operationalKey]) -Type String
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
