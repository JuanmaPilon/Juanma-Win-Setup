[CmdletBinding()]
param(
    [string]$Destination = "$HOME\Win-Setup-Backups",
    [int]$Keep = 5,
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDirectory = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$repoRoot = Split-Path -Parent $scriptDirectory

if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = Join-Path $repoRoot 'private-configs'
}

if (-not (Test-Path $SourceRoot)) {
    Write-Host "private-configs folder not found: $SourceRoot" -ForegroundColor Yellow
    return
}

if ([System.IO.Path]::IsPathRooted($Destination)) {
    $resolvedDestination = [System.IO.Path]::GetFullPath($Destination)
}
else {
    $resolvedDestination = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Destination))
}

$repoFullPath = [System.IO.Path]::GetFullPath($repoRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
$repoPrefix = $repoFullPath + [System.IO.Path]::DirectorySeparatorChar
if ($resolvedDestination.StartsWith($repoPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Host "Refusing to write the backup inside the repository ($resolvedDestination). Use a path outside the repo." -ForegroundColor Red
    return
}

if (-not (Test-Path $resolvedDestination)) {
    New-Item -ItemType Directory -Path $resolvedDestination -Force | Out-Null
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$zipPath = Join-Path $resolvedDestination "Win-Setup-private-configs-$timestamp.zip"

Compress-Archive -Path (Join-Path $SourceRoot '*') -DestinationPath $zipPath -CompressionLevel Optimal -Force

$zipInfo = Get-Item $zipPath
Write-Host "Backup created: $($zipInfo.FullName) ($([math]::Round($zipInfo.Length/1MB,2)) MB)" -ForegroundColor Green

# Rotation: keep only the newest $Keep archives
$backups = @(Get-ChildItem -Path $resolvedDestination -Filter 'Win-Setup-private-configs-*.zip' -File |
    Sort-Object LastWriteTime -Descending)

$backupsCount = $backups.Count

if ($backupsCount -gt $Keep) {
    $backups | Select-Object -Skip $Keep | ForEach-Object {
        Remove-Item -Path $_.FullName -Force
        Write-Host "Rotated out old backup: $($_.Name)" -ForegroundColor DarkGray
    }
    $backupsCount = $Keep
}

Write-Host "Keeping the newest $backupsCount backup(s) in $resolvedDestination" -ForegroundColor Cyan
Write-Host 'Remember: copy this ZIP to another machine or external drive regularly (it is your disaster-recovery bundle).' -ForegroundColor Yellow
