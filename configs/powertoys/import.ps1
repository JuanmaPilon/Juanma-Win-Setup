[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

try {
    Import-Module (Join-Path $RepositoryRoot 'modules/SetupHelpers.psm1') -Force
}
catch {
    Write-Host "[error] Failed to import SetupHelpers module: $_" -ForegroundColor Red
    return
}

Write-SetupStep 'Preparing PowerToys configuration import'

$privateConfigSource = Join-Path $RepositoryRoot 'private-configs/powertoys'
$publicConfigSource = Join-Path $RepositoryRoot 'configs/powertoys'
$configSource = if (Test-Path $privateConfigSource) { $privateConfigSource } else { $publicConfigSource }
$configSource = [System.IO.Path]::GetFullPath($configSource)
$powertoysConfigPath = Join-Path $env:LOCALAPPDATA 'Microsoft/PowerToys'

if (-not (Test-Path $configSource)) {
    Write-SetupWarning 'PowerToys config source directory not found.'
    return
}

if (-not (Test-Path $powertoysConfigPath)) {
    Write-SetupWarning 'PowerToys is not installed yet or its config folder is missing.'
    return
}

if (-not $DryRun) {
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -like 'PowerToys*' -or $_.ProcessName -like 'CmdPal*' } |
        Stop-Process -Force -ErrorAction SilentlyContinue
}

function Test-ShouldImportPowerToysFile {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $normalizedPath = $RelativePath -replace '\\', '/'

    if ($normalizedPath -match '(^|/)Logs(/|$)' -or $normalizedPath -match '(^|/)RunnerLogs(/|$)' -or $normalizedPath -match '(^|/)UpdateLogs(/|$)' -or $normalizedPath -match '(^|/)Updates(/|$)') {
        return $false
    }

    if ($normalizedPath -match '(^|/)ptb-backup(/|$)') {
        return $false
    }

    if ($normalizedPath -match '(^|/)runtime-backup(/|$)') {
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
        'README.md' { return $false }
        'import.ps1' { return $false }
    }

    return $true
}

if ($DryRun) {
    Write-SetupWarning 'Dry run mode enabled: no PowerToys files will be modified.'
    Get-ChildItem -Path $configSource -Recurse -File -ErrorAction SilentlyContinue |
        ForEach-Object {
            $relativePath = $_.FullName.Substring($configSource.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
            if (Test-ShouldImportPowerToysFile -RelativePath $relativePath) { Write-SetupInfo "[DryRun] Would import PowerToys file: $relativePath" }
        }
    $runtimeRoot = Join-Path $configSource 'runtime-backup'
    if (Test-Path $runtimeRoot) {
        Write-SetupInfo "[DryRun] Would restore $((@(Get-ChildItem $runtimeRoot -Recurse -File)).Count) runtime backup file(s) to LocalAppData\PowerToys"
    }
    $ptbRoot = Join-Path $configSource 'ptb-backup'
    if (Test-Path $ptbRoot) {
        Write-SetupInfo "[DryRun] Would restore $((@(Get-ChildItem $ptbRoot -File)).Count) .ptb backup file(s) to Documents\PowerToys\Backup"
    }
    Write-SetupSuccess 'Dry run completed.'
    return
}

$runtimeSourceRoot = Join-Path $configSource 'runtime-backup'
$runtimeTargetRoot = Join-Path $env:LOCALAPPDATA 'PowerToys'

if (Test-Path $runtimeSourceRoot) {
    $runtimeFiles = Get-ChildItem -Path $runtimeSourceRoot -Recurse -File -ErrorAction SilentlyContinue
    foreach ($runtimeFile in $runtimeFiles) {
        $relativeRuntimePath = $runtimeFile.FullName.Substring($runtimeSourceRoot.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        $runtimeDestinationPath = Join-Path $runtimeTargetRoot $relativeRuntimePath
        $runtimeDestinationDirectory = Split-Path -Parent $runtimeDestinationPath

        try {
            if (-not (Test-Path $runtimeDestinationDirectory)) {
                New-Item -ItemType Directory -Path $runtimeDestinationDirectory -Force | Out-Null
            }

            Copy-Item -Path $runtimeFile.FullName -Destination $runtimeDestinationPath -Force
            Write-SetupInfo "Imported PowerToys runtime file: $relativeRuntimePath"
        }
        catch {
            Write-SetupWarning "Failed to import PowerToys runtime file '$relativeRuntimePath': $($_.Exception.Message)"
        }
    }
}

$documentsPath = [Environment]::GetFolderPath('MyDocuments')
$officialBackupRoot = Join-Path $documentsPath 'PowerToys/Backup'
$ptbSourceRoot = Join-Path $configSource 'ptb-backup'

if (Test-Path $ptbSourceRoot) {
    try {
        if (-not (Test-Path $officialBackupRoot)) {
            New-Item -ItemType Directory -Path $officialBackupRoot -Force | Out-Null
        }

        $ptbFiles = Get-ChildItem -Path $ptbSourceRoot -Filter '*.ptb' -File -ErrorAction SilentlyContinue
        foreach ($ptbFile in $ptbFiles) {
            $destinationPath = Join-Path $officialBackupRoot $ptbFile.Name
            Copy-Item -Path $ptbFile.FullName -Destination $destinationPath -Force
            Write-SetupInfo "Restored PowerToys official backup file: $($ptbFile.Name)"
        }
    }
    catch {
        Write-SetupWarning "Failed to restore PowerToys .ptb backup files: $($_.Exception.Message)"
    }
}

$filesToCopy = Get-ChildItem -Path $configSource -Recurse -File -ErrorAction SilentlyContinue |
    ForEach-Object {
        $relativePath = $_.FullName.Substring($configSource.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        if (Test-ShouldImportPowerToysFile -RelativePath $relativePath) {
            $_
        }
    }

if (-not $filesToCopy) {
    Write-SetupWarning 'No PowerToys configuration files were found to import.'
    return
}

foreach ($sourceFile in $filesToCopy) {
    $relativePath = $sourceFile.FullName.Substring($configSource.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $destinationPath = Join-Path $powertoysConfigPath $relativePath
    $destinationDirectory = Split-Path -Parent $destinationPath

    try {
        if (-not (Test-Path $destinationDirectory)) {
            New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
        }

        Copy-Item -Path $sourceFile.FullName -Destination $destinationPath -Force
        Write-SetupInfo "Imported PowerToys file: $relativePath"
    }
    catch {
        Write-SetupWarning "Failed to import PowerToys file '$relativePath': $($_.Exception.Message)"
    }
}

try {
    $powerToysExe = Get-Command 'PowerToys.exe' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
    if ($powerToysExe) {
        Start-Process $powerToysExe | Out-Null
    }
    else {
        Start-Process 'PowerToys.exe' -ErrorAction Stop | Out-Null
    }
    Write-SetupSuccess 'Restarted PowerToys to apply restored settings.'
}
catch {
    Write-SetupWarning 'Could not restart PowerToys automatically. Start it manually if needed.'
}

Write-SetupSuccess 'PowerToys configuration import completed.'
