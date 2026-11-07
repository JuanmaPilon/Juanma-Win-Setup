[CmdletBinding()]
param(
    [string]$OutputRoot = 'private-configs/windhawk',
    [string]$InstallPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDirectory = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$repoRoot = Split-Path -Parent $scriptDirectory

$resolvedOutputRoot = if ([System.IO.Path]::IsPathRooted($OutputRoot)) {
    [System.IO.Path]::GetFullPath($OutputRoot)
}
else {
    [System.IO.Path]::GetFullPath((Join-Path $repoRoot $OutputRoot))
}

if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    $InstallPath = Join-Path $env:LOCALAPPDATA 'Programs\Windhawk'
}

$iniPath = Join-Path $InstallPath 'windhawk.ini'
if (-not (Test-Path $iniPath)) {
    Write-Host "Windhawk portable install not found at $InstallPath. Install it with: windhawk_setup.exe /S /PORTABLE /D=<path>" -ForegroundColor Yellow
    return
}

$iniContent = Get-Content $iniPath -Raw
if ($iniContent -notmatch 'Portable\s*=\s*1') {
    Write-Host 'Windhawk is installed but not in portable mode. This module only supports portable installs.' -ForegroundColor Yellow
    return
}

$dataRoot = Join-Path $InstallPath 'AppData'
if (-not (Test-Path $dataRoot)) {
    Write-Host "Windhawk data folder not found: $dataRoot" -ForegroundColor Yellow
    return
}

if (-not (Test-Path $resolvedOutputRoot)) {
    New-Item -ItemType Directory -Path $resolvedOutputRoot -Force | Out-Null
}

# Regenerate a clean mirror of the configuration every time
$previousData = Join-Path $resolvedOutputRoot 'data'
if (Test-Path $previousData) {
    Remove-Item -Path $previousData -Recurse -Force
}

function Test-ShouldExportWindhawkFile {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $normalizedPath = $RelativePath -replace '\\', '/'

    # Allowlist: only real configuration, never binaries or WebView/VS Code caches
    if ($normalizedPath -eq 'settings.ini') { return $true }
    if ($normalizedPath -eq 'userprofile.json') { return $true }
    if ($normalizedPath -eq 'Engine/settings.ini') { return $true }
    if ($normalizedPath -match '^Engine/Mods/[^/]+\.ini$') { return $true }
    if ($normalizedPath -match '^Engine/ModsWritable/[^/]+\.ini$') { return $true }
    if ($normalizedPath -match '^Engine/ModsWritable/mod-storage/') { return $true }
    if ($normalizedPath -match '^ModsSource/[^/]+\.wh\.cpp$') { return $true }
    if ($normalizedPath -match '^UIData/user-data/User/[^/]+$') { return $true }

    return $false
}

$exported = 0
$files = Get-ChildItem -Path $dataRoot -Recurse -File -ErrorAction SilentlyContinue
foreach ($file in $files) {
    $relativePath = $file.FullName.Substring($dataRoot.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    if (-not (Test-ShouldExportWindhawkFile -RelativePath $relativePath)) {
        continue
    }

    $destinationPath = Join-Path (Join-Path $resolvedOutputRoot 'data') $relativePath
    $destinationDirectory = Split-Path -Parent $destinationPath
    if (-not (Test-Path $destinationDirectory)) {
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    }

    Copy-Item -Path $file.FullName -Destination $destinationPath -Force
    Write-Host "Exported Windhawk file: data/$relativePath" -ForegroundColor Green
    $exported++
}

Write-Host "Windhawk configuration exported to $resolvedOutputRoot ($exported files)" -ForegroundColor Green
