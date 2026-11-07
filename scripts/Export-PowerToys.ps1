[CmdletBinding()]
param(
    [string]$OutputRoot = 'private-configs/powertoys'
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

$candidatePaths = @(
    (Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys'),
    (Join-Path $env:APPDATA 'Microsoft\PowerToys'),
    (Join-Path $env:LOCALAPPDATA 'PowerToys')
)

$sourceRoot = $null
foreach ($candidate in $candidatePaths) {
    if (Test-Path $candidate) {
        $sourceRoot = $candidate
        break
    }
}

if (-not $sourceRoot) {
    Write-Host 'PowerToys configuration directory not found in the usual locations.' -ForegroundColor Yellow
    return
}

if (-not (Test-Path $resolvedOutputRoot)) {
    New-Item -ItemType Directory -Path $resolvedOutputRoot -Force | Out-Null
}

Get-Process -Name 'PowerToys' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process -Name 'PowerToys.Settings' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

function Test-ShouldExportPowerToysFile {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $normalizedPath = $RelativePath -replace '\\', '/'

    if ($normalizedPath -match '(^|/)Logs(/|$)' -or $normalizedPath -match '(^|/)RunnerLogs(/|$)' -or $normalizedPath -match '(^|/)UpdateLogs(/|$)' -or $normalizedPath -match '(^|/)Updates(/|$)') {
        return $false
    }

    if ($normalizedPath -match '\.(log|tmp|bak|lock)$' -or $normalizedPath -match '\.cli-lock$') {
        return $false
    }

    switch ($RelativePath) {
        'last_version_run.json' { return $false }
        'log_settings.json' { return $false }
        'oobe_settings.json' { return $false }
        'settings-telemetry.json' { return $false }
        'UpdateState.json' { return $false }
        'settings-placement.json' { return $false }
    }

    return $true
}

$filesToExport = Get-ChildItem -Path $sourceRoot -Recurse -File -ErrorAction SilentlyContinue
if (-not $filesToExport) {
    Write-Host "No PowerToys configuration files were found in $sourceRoot" -ForegroundColor Yellow
    return
}

foreach ($sourceFile in $filesToExport) {
    $relativePath = $sourceFile.FullName.Substring($sourceRoot.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    if (-not (Test-ShouldExportPowerToysFile -RelativePath $relativePath)) {
        continue
    }

    $destinationPath = Join-Path $resolvedOutputRoot $relativePath
    $destinationDirectory = Split-Path -Parent $destinationPath
    if (-not (Test-Path $destinationDirectory)) {
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    }

    Copy-Item -Path $sourceFile.FullName -Destination $destinationPath -Force
    Write-Host "Exported PowerToys file: $relativePath" -ForegroundColor Green
}

$runtimeRoot = Join-Path $env:LOCALAPPDATA 'PowerToys'
$runtimeDestinationRoot = Join-Path $resolvedOutputRoot 'runtime-backup'
if (Test-Path $runtimeRoot) {
    $runtimeFiles = Get-ChildItem -Path $runtimeRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ieq 'backup_restore_settings.json' }

    foreach ($runtimeFile in $runtimeFiles) {
        $relativeRuntimePath = $runtimeFile.FullName.Substring($runtimeRoot.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        $runtimeDestinationPath = Join-Path $runtimeDestinationRoot $relativeRuntimePath
        $runtimeDestinationDirectory = Split-Path -Parent $runtimeDestinationPath
        if (-not (Test-Path $runtimeDestinationDirectory)) {
            New-Item -ItemType Directory -Path $runtimeDestinationDirectory -Force | Out-Null
        }

        Copy-Item -Path $runtimeFile.FullName -Destination $runtimeDestinationPath -Force
        Write-Host "Exported PowerToys runtime backup file: runtime-backup/$relativeRuntimePath" -ForegroundColor Green
    }
}

$documentsPath = [Environment]::GetFolderPath('MyDocuments')
$officialBackupRoot = Join-Path $documentsPath 'PowerToys\Backup'
$officialBackupDestination = Join-Path $resolvedOutputRoot 'ptb-backup'

if (Test-Path $officialBackupRoot) {
    $ptbFiles = Get-ChildItem -Path $officialBackupRoot -Filter '*.ptb' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    if ($ptbFiles) {
        if (-not (Test-Path $officialBackupDestination)) {
            New-Item -ItemType Directory -Path $officialBackupDestination -Force | Out-Null
        }

        foreach ($ptbFile in $ptbFiles) {
            $destinationPath = Join-Path $officialBackupDestination $ptbFile.Name
            Copy-Item -Path $ptbFile.FullName -Destination $destinationPath -Force
            Write-Host "Exported PowerToys official backup: ptb-backup/$($ptbFile.Name)" -ForegroundColor Green
        }
    }
    else {
        Write-Host 'No .ptb backup files were found in Documents\PowerToys\Backup.' -ForegroundColor Yellow
    }
}
else {
    Write-Host 'PowerToys official backup folder was not found in Documents\PowerToys\Backup.' -ForegroundColor Yellow
}

Write-Host "PowerToys configuration exported to $resolvedOutputRoot" -ForegroundColor Green
