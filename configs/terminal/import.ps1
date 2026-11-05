[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Import-Module (Join-Path $RepositoryRoot 'modules/SetupHelpers.psm1') -Force

Write-SetupStep 'Preparing terminal configuration import'

$privateSourceRoot = Join-Path $RepositoryRoot 'private-configs/terminal'
$publicSourceRoot = Join-Path $RepositoryRoot 'configs/terminal'
$sourceRoot = if (Test-Path $privateSourceRoot) { $privateSourceRoot } else { $publicSourceRoot }

if (-not (Test-Path $sourceRoot)) {
    Write-SetupWarning 'Terminal config source directory not found.'
    return
}

if ($DryRun) {
    Write-SetupWarning 'Dry run mode enabled: no terminal files will be modified.'
}

$documentsPath = [Environment]::GetFolderPath('MyDocuments')

function Import-TerminalFile {
    param(
        [string]$Source,
        [string]$Destination,
        [string]$Description
    )

    if ([string]::IsNullOrWhiteSpace($Source) -or -not (Test-Path $Source)) {
        return
    }

    if ($DryRun) {
        Write-SetupInfo "[DryRun] Would import $Description -> $Destination"
        return
    }

    try {
        $destinationDirectory = Split-Path -Parent $Destination
        if (-not (Test-Path $destinationDirectory)) {
            New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
        }

        if (Test-Path $Destination) {
            $backupPath = "$Destination.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
            Copy-Item -Path $Destination -Destination $backupPath -Force
            Write-SetupInfo "Backed up existing ${Description}: $backupPath"
        }

        Copy-Item -Path $Source -Destination $Destination -Force
        Write-SetupSuccess "Imported $Description"
    }
    catch {
        Write-SetupWarning "Failed to import ${Description}: $($_.Exception.Message)"
    }
}

function Import-TerminalDirectory {
    param(
        [string]$SourceDirectory,
        [string]$DestinationDirectory,
        [string]$FilePattern,
        [string]$Description
    )

    if (-not (Test-Path $SourceDirectory)) {
        return
    }

    $files = Get-ChildItem -Path $SourceDirectory -Filter $FilePattern -File -ErrorAction SilentlyContinue
    foreach ($file in $files) {
        Import-TerminalFile -Source $file.FullName -Destination (Join-Path $DestinationDirectory $file.Name) -Description "$Description $($file.Name)"
    }
}

# Windows Terminal settings
$windowsTerminalStable = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
$windowsTerminalPreview = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'
$windowsTerminalTarget = if (Test-Path $windowsTerminalStable) { $windowsTerminalStable } elseif (Test-Path $windowsTerminalPreview) { $windowsTerminalPreview } else { $windowsTerminalStable }

Import-TerminalFile -Source (Join-Path $sourceRoot 'windows-terminal/settings.json') -Destination $windowsTerminalTarget -Description 'Windows Terminal settings'

# PowerShell profiles
Import-TerminalFile -Source (Join-Path $sourceRoot 'profiles/PowerShell/Microsoft.PowerShell_profile.ps1') -Destination (Join-Path $documentsPath 'PowerShell\Microsoft.PowerShell_profile.ps1') -Description 'PowerShell 7 profile'
Import-TerminalFile -Source (Join-Path $sourceRoot 'profiles/WindowsPowerShell/Microsoft.PowerShell_profile.ps1') -Destination (Join-Path $documentsPath 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1') -Description 'Windows PowerShell 5.1 profile'

# Oh My Posh themes
Import-TerminalDirectory -SourceDirectory (Join-Path $sourceRoot 'oh-my-posh') -DestinationDirectory (Join-Path $HOME '.config\oh-my-posh') -FilePattern '*.omp.json' -Description 'Oh My Posh theme'

# PowerShell completions
Import-TerminalDirectory -SourceDirectory (Join-Path $sourceRoot 'completions') -DestinationDirectory (Join-Path $HOME '.config\powershell\completions') -FilePattern '*.ps1' -Description 'completion script'

# fastfetch config
Import-TerminalFile -Source (Join-Path $sourceRoot 'fastfetch/config.jsonc') -Destination (Join-Path $env:APPDATA 'fastfetch/config.jsonc') -Description 'fastfetch config'

# Dependency checks
if (-not (Get-Command 'oh-my-posh' -ErrorAction SilentlyContinue)) {
    Write-SetupWarning 'Oh My Posh is not installed. Run the Winget app install (JanDeDobbeleer.OhMyPosh) and reopen the terminal.'
}

if (-not (Get-Command 'fastfetch' -ErrorAction SilentlyContinue)) {
    Write-SetupWarning 'fastfetch is not installed. Run the Winget app install (Fastfetch-cli.Fastfetch).'
}

if (-not (Get-Module -ListAvailable -Name Terminal-Icons)) {
    if ($DryRun) {
        Write-SetupInfo '[DryRun] Would install the Terminal-Icons PowerShell module.'
    }
    else {
        try {
            Write-SetupInfo 'Installing Terminal-Icons PowerShell module.'
            Install-Module Terminal-Icons -Scope CurrentUser -Force -Repository PSGallery -ErrorAction Stop
            Write-SetupSuccess 'Terminal-Icons module installed.'
        }
        catch {
            Write-SetupWarning "Could not install Terminal-Icons automatically: $($_.Exception.Message). Run: Install-Module Terminal-Icons -Scope CurrentUser -Force"
        }
    }
}

$psReadLineVersion = (Get-Module -ListAvailable PSReadLine | Select-Object -First 1).Version
if ($psReadLineVersion -and $psReadLineVersion -lt [version]'2.1') {
    Write-SetupWarning "PSReadLine $psReadLineVersion is too old for predictive suggestions. Update with: Install-Module PSReadLine -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber"
}

Write-SetupSuccess 'Terminal configuration import completed.'
