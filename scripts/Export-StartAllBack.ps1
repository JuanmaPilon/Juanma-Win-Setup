[CmdletBinding()]
param(
    [string]$OutputRoot,
    [switch]$IncludeShellState,
    [switch]$IncludePinnedApps
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDirectory = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$repoRoot = Split-Path -Parent $scriptDirectory

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = 'private-configs/startallback'
}

$resolvedOutputRoot = if ([System.IO.Path]::IsPathRooted($OutputRoot)) {
    [System.IO.Path]::GetFullPath($OutputRoot)
}
else {
    [System.IO.Path]::GetFullPath((Join-Path $repoRoot $OutputRoot))
}

if (-not (Test-Path $resolvedOutputRoot)) {
    New-Item -ItemType Directory -Path $resolvedOutputRoot -Force | Out-Null
}

$startAllBackUserRegPath = Join-Path $resolvedOutputRoot 'StartIsBack-HKCU.reg'
$startAllBackMachineRegPath = Join-Path $resolvedOutputRoot 'StartIsBack-HKLM.reg'

if (-not (Test-Path 'HKCU:\Software\StartIsBack')) {
    Write-Host 'StartAllBack is not installed on this machine; skipping StartAllBack export.' -ForegroundColor Yellow
    return
}

try {
    reg export 'HKCU\Software\StartIsBack' $startAllBackUserRegPath /y | Out-Null
    Write-Host 'Exported StartAllBack user registry key.' -ForegroundColor Green
}
catch {
    Write-Host 'Could not export HKCU\Software\StartIsBack.' -ForegroundColor Yellow
}

if (Test-Path 'HKLM:\SOFTWARE\StartIsBack') {
    try {
        reg export 'HKLM\SOFTWARE\StartIsBack' $startAllBackMachineRegPath /y | Out-Null
        Write-Host 'Exported StartAllBack machine registry key.' -ForegroundColor Green
    }
    catch {
        Write-Host 'HKLM\SOFTWARE\StartIsBack was not exported (insufficient permissions).' -ForegroundColor Yellow
    }
}
else {
    Write-Host 'No StartAllBack machine registry key found (normal when per-user install).' -ForegroundColor DarkGray
}

if ($IncludeShellState) {
    try {
        reg export 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' (Join-Path $resolvedOutputRoot 'Explorer-Advanced.reg') /y | Out-Null
        reg export 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3' (Join-Path $resolvedOutputRoot 'Explorer-StuckRects3.reg') /y | Out-Null
        Write-Host 'Exported Explorer shell state keys.' -ForegroundColor Green
    }
    catch {
        Write-Host 'Failed to export one or more Explorer shell state keys.' -ForegroundColor Yellow
    }
}

if ($IncludePinnedApps) {
    try {
        reg export 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband' (Join-Path $resolvedOutputRoot 'Explorer-Taskband.reg') /y | Out-Null
        Write-Host 'Exported Explorer taskbar pinned apps key.' -ForegroundColor Green
    }
    catch {
        Write-Host 'Could not export Explorer Taskband key.' -ForegroundColor Yellow
    }
}

$candidatePaths = @(
    (Join-Path $env:LOCALAPPDATA 'StartAllBack'),
    (Join-Path $env:LOCALAPPDATA 'Programs\StartAllBack'),
    (Join-Path $env:APPDATA 'StartAllBack'),
    (Join-Path $env:APPDATA 'Programs\StartAllBack')
)

$fileSourceRoot = $null
foreach ($candidate in $candidatePaths) {
    if (Test-Path $candidate) {
        $fileSourceRoot = $candidate
        break
    }
}

if (-not $fileSourceRoot) {
    Write-Host 'StartAllBack local config directory was not found. Registry export may still be usable.' -ForegroundColor Yellow
    return
}

$filesOutputRoot = Join-Path $resolvedOutputRoot 'files'
if (-not (Test-Path $filesOutputRoot)) {
    New-Item -ItemType Directory -Path $filesOutputRoot -Force | Out-Null
}

$filesToExport = Get-ChildItem -Path $fileSourceRoot -Recurse -File -ErrorAction SilentlyContinue
foreach ($sourceFile in $filesToExport) {
    $relativePath = $sourceFile.FullName.Substring($fileSourceRoot.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $destinationPath = Join-Path $filesOutputRoot $relativePath
    $destinationDirectory = Split-Path -Parent $destinationPath
    if (-not (Test-Path $destinationDirectory)) {
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    }

    Copy-Item -Path $sourceFile.FullName -Destination $destinationPath -Force
    Write-Host "Exported StartAllBack file: $relativePath" -ForegroundColor Green
}

Write-Host "StartAllBack configuration exported to $resolvedOutputRoot" -ForegroundColor Green
