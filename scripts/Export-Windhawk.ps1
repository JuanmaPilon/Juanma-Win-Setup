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

if (-not (Test-Path $resolvedOutputRoot)) {
    New-Item -ItemType Directory -Path $resolvedOutputRoot -Force | Out-Null
}

# Mode detection: normal (registry) install takes precedence
$normalIni = Join-Path $env:ProgramFiles 'Windhawk\windhawk.ini'
$normalMode = $false
if (Test-Path $normalIni) {
    $normalIniContent = Get-Content $normalIni -Raw
    if ($normalIniContent -match 'Portable\s*=\s*0') {
        $normalMode = $true
    }
}

if ($normalMode) {
    $dataDir = Join-Path $resolvedOutputRoot 'data'
    if (Test-Path $dataDir) {
        Remove-Item -Path $dataDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    Set-Content -Path (Join-Path $dataDir 'mode.txt') -Value 'registry'

    try {
        reg export 'HKLM\SOFTWARE\Windhawk' (Join-Path $dataDir 'windhawk-hklm.reg') /y | Out-Null
        Write-Host 'Exported HKLM\SOFTWARE\Windhawk' -ForegroundColor Green
    }
    catch {
        Write-Host 'Could not export HKLM\SOFTWARE\Windhawk' -ForegroundColor Yellow
    }

    if (Test-Path 'HKCU:\Software\Windhawk') {
        try {
            reg export 'HKCU\Software\Windhawk' (Join-Path $dataDir 'windhawk-hkcu.reg') /y | Out-Null
            Write-Host 'Exported HKCU\Software\Windhawk' -ForegroundColor Green
        }
        catch {
            Write-Host 'Could not export HKCU\Software\Windhawk' -ForegroundColor Yellow
        }
    }

    $programDataRoot = Join-Path $env:ProgramData 'Windhawk'
    $sourceFiles = Get-ChildItem (Join-Path $programDataRoot 'ModsSource') -Filter '*.wh.cpp' -File -ErrorAction SilentlyContinue
    foreach ($sourceFile in $sourceFiles) {
        $destinationDir = Join-Path $dataDir 'ModsSource'
        if (-not (Test-Path $destinationDir)) { New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null }
        Copy-Item $sourceFile.FullName -Destination (Join-Path $destinationDir $sourceFile.Name) -Force
        Write-Host "Exported Windhawk mod source: ModsSource/$($sourceFile.Name)" -ForegroundColor Green
    }

    $userProfile = Join-Path $programDataRoot 'userprofile.json'
    if (Test-Path $userProfile) {
        Copy-Item $userProfile -Destination (Join-Path $dataDir 'userprofile.json') -Force
        Write-Host 'Exported Windhawk user profile' -ForegroundColor Green
    }

    # Compiled mod DLLs: without these the engine cannot load any mod, even when the
    # registry and user profile are restored correctly.
    $modsKey = 'HKLM:\SOFTWARE\Windhawk\Engine\Mods'
    $manifest = @()
    if (Test-Path $modsKey) {
        foreach ($modKey in Get-ChildItem $modsKey -ErrorAction SilentlyContinue) {
            $modId = $modKey.PSChildName
            $modProps = Get-ItemProperty $modKey.PSPath -ErrorAction SilentlyContinue

            $libraryFileName = if ($modProps -and $modProps.PSObject.Properties.Name -contains 'LibraryFileName') { $modProps.LibraryFileName } else { $null }
            $modVersion = if ($modProps -and $modProps.PSObject.Properties.Name -contains 'Version') { $modProps.Version } else { '' }
            $modArch = if ($modProps -and $modProps.PSObject.Properties.Name -contains 'Architecture') { $modProps.Architecture } else { '' }
            $modDisabled = if ($modProps -and $modProps.PSObject.Properties.Name -contains 'Disabled') { [int]$modProps.Disabled } else { 0 }

            $archCandidates = if ($modArch -match 'x86-64|x64|64') { @('64', '32') } else { @('32', '64') }
            $librarySource = $null
            $libraryArch = $null
            if ($libraryFileName) {
                foreach ($arch in $archCandidates) {
                    $candidatePath = Join-Path $programDataRoot "Engine/Mods/$arch/$libraryFileName"
                    if (Test-Path $candidatePath) {
                        $librarySource = $candidatePath
                        $libraryArch = $arch
                        break
                    }
                }
            }

            if ($librarySource) {
                $engineTarget = Join-Path (Join-Path $dataDir 'Engine/Mods') $libraryArch
                if (-not (Test-Path $engineTarget)) { New-Item -ItemType Directory -Path $engineTarget -Force | Out-Null }
                Copy-Item $librarySource -Destination (Join-Path $engineTarget $libraryFileName) -Force
                Write-Host "Exported compiled Windhawk mod: Engine/Mods/$libraryArch/$libraryFileName" -ForegroundColor Green
            }
            elseif ($libraryFileName) {
                Write-Host "WARNING: compiled binary for '$modId' not found ($libraryFileName). It will need recompiling on the target." -ForegroundColor Yellow
            }

            $manifest += [pscustomobject]@{
                id              = $modId
                version         = $modVersion
                architecture    = $modArch
                libraryFileName = $libraryFileName
                disabled        = $modDisabled
                compiled        = [bool]$librarySource
            }
        }
    }

    # Per-mod writable storage (mods that keep their own state outside the registry).
    # mod-status/ is a transient runtime cache, never settings.
    $writableRoot = Join-Path $programDataRoot 'Engine/ModsWritable'
    if (Test-Path $writableRoot) {
        foreach ($writableFile in Get-ChildItem $writableRoot -Recurse -File -ErrorAction SilentlyContinue) {
            if ($writableFile.Name -eq 'warning.txt') { continue }
            $relativeWritable = $writableFile.FullName.Substring($writableRoot.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
            if ($relativeWritable -match '^(?i)mod-status[\\/]') { continue }
            $writableTarget = Join-Path (Join-Path $dataDir 'Engine/ModsWritable') (Split-Path -Parent $relativeWritable)
            if ($writableTarget -and -not (Test-Path $writableTarget)) { New-Item -ItemType Directory -Path $writableTarget -Force | Out-Null }
            Copy-Item $writableFile.FullName -Destination (Join-Path (Join-Path $dataDir 'Engine/ModsWritable') $relativeWritable) -Force
            Write-Host "Exported Windhawk mod storage: Engine/ModsWritable/$relativeWritable" -ForegroundColor Green
        }
    }

    if ($manifest.Count -gt 0) {
        $manifest | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $dataDir 'mods-manifest.json')
        $compiled = @($manifest | Where-Object { $_.compiled }).Count
        Write-Host "Exported Windhawk mod manifest: $($manifest.Count) mod(s), $compiled with compiled binary" -ForegroundColor Green
    }

    Write-Host "Windhawk configuration exported to $resolvedOutputRoot (registry mode)" -ForegroundColor Green
    return
}

if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    $InstallPath = Join-Path $env:LOCALAPPDATA 'Programs\Windhawk'
}

$iniPath = Join-Path $InstallPath 'windhawk.ini'
if (-not (Test-Path $iniPath)) {
    Write-Host "Windhawk not found (neither normal install in Program Files nor portable at $InstallPath)." -ForegroundColor Yellow
    return
}

$iniContent = Get-Content $iniPath -Raw
if ($iniContent -notmatch 'Portable\s*=\s*1') {
    Write-Host 'Windhawk portable install not detected. Normal installs are handled in registry mode.' -ForegroundColor Yellow
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
New-Item -ItemType Directory -Path $previousData -Force | Out-Null
Set-Content -Path (Join-Path $previousData 'mode.txt') -Value 'portable'

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
