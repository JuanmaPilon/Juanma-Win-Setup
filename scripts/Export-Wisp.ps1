[CmdletBinding()]
param(
    [string]$OutputRoot = 'private-configs/wisp',
    [string]$SourceRoot
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

if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = Join-Path $env:APPDATA 'wisp'
}

if (-not (Test-Path $SourceRoot)) {
    Write-Host "Wisp config folder not found: $SourceRoot (is Wisp installed and opened once?)" -ForegroundColor Yellow
    return
}

# Regenerate a clean mirror every time so deleted keys/surfaces don't linger
if (Test-Path $resolvedOutputRoot) {
    Remove-Item -Path $resolvedOutputRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $resolvedOutputRoot -Force | Out-Null

$configPath = Join-Path $SourceRoot 'config.toml'
if (-not (Test-Path $configPath)) {
    Write-Host "Wisp config.toml not found in $SourceRoot." -ForegroundColor Yellow
    return
}

Copy-Item $configPath -Destination (Join-Path $resolvedOutputRoot 'config.toml') -Force
Write-Host 'Exported Wisp config: config.toml' -ForegroundColor Green

# Custom launcher panels (optional)
$surfacesRoot = Join-Path $SourceRoot 'surfaces'
if (Test-Path $surfacesRoot) {
    $surfaceFiles = @(Get-ChildItem $surfacesRoot -File -Filter '*.toml' -ErrorAction SilentlyContinue)
    if ($surfaceFiles.Count -gt 0) {
        $surfacesTarget = Join-Path $resolvedOutputRoot 'surfaces'
        New-Item -ItemType Directory -Path $surfacesTarget -Force | Out-Null
        foreach ($surfaceFile in $surfaceFiles) {
            Copy-Item $surfaceFile.FullName -Destination (Join-Path $surfacesTarget $surfaceFile.Name) -Force
            Write-Host "Exported Wisp panel: surfaces/$($surfaceFile.Name)" -ForegroundColor Green
        }
    }
}

# Record where the binary actually lives: Wisp has no winget package yet, so the
# import needs to know if the install path is portable (never a Downloads folder).
function ConvertTo-PortablePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ($env:USERPROFILE -and $Path.StartsWith($env:USERPROFILE, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $Path.Replace($env:USERPROFILE, '%USERPROFILE%')
    }
    if ($env:LOCALAPPDATA -and $Path.StartsWith($env:LOCALAPPDATA, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $Path.Replace($env:LOCALAPPDATA, '%LOCALAPPDATA%')
    }
    if ($env:ProgramFiles -and $Path.StartsWith($env:ProgramFiles, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $Path.Replace($env:ProgramFiles, '%ProgramFiles%')
    }

    return $Path
}

$runningWisp = Get-Process -Name 'wisp' -ErrorAction SilentlyContinue | Select-Object -First 1
$exePath = $null
if ($runningWisp -and $runningWisp.Path) {
    $exePath = $runningWisp.Path
}
else {
    $defaultExe = Join-Path $env:LOCALAPPDATA 'Programs\Wisp\wisp.exe'
    if (Test-Path $defaultExe) { $exePath = $defaultExe }
}

$version = 'unknown'
if ($exePath -and (Test-Path $exePath)) {
    $fileVersion = (Get-Item $exePath).VersionInfo
    if ($fileVersion.ProductVersion) { $version = $fileVersion.ProductVersion }
    elseif ($fileVersion.FileVersion) { $version = $fileVersion.FileVersion }
}

$metaLines = @(
    "version=$version"
    "exe=$(if ($exePath) { ConvertTo-PortablePath -Path $exePath } else { 'not-found' })"
    "expected=%LOCALAPPDATA%\Programs\Wisp\wisp.exe"
)
Set-Content -Path (Join-Path $resolvedOutputRoot '_install.txt') -Value $metaLines -Encoding UTF8

if ($exePath -and $exePath -notlike '*\Programs\Wisp\*') {
    Write-Host "WARNING: Wisp runs from $(ConvertTo-PortablePath -Path $exePath)." -ForegroundColor Yellow
    Write-Host '         Move it to %LOCALAPPDATA%\Programs\Wisp and fix the "Wisp" Run entry, or the startup backup will point to a dead path.' -ForegroundColor Yellow
}

Write-Host "Wisp configuration exported to $resolvedOutputRoot (version $version)" -ForegroundColor Green
