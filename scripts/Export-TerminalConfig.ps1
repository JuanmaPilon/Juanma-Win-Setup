[CmdletBinding()]
param(
    [string]$OutputRoot = 'private-configs/terminal'
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

function Export-TerminalFile {
    param(
        [string]$Source,
        [string]$Destination,
        [string]$Description
    )

    if ([string]::IsNullOrWhiteSpace($Source) -or -not (Test-Path $Source)) {
        Write-Host "Skipped $Description (not found)." -ForegroundColor Yellow
        return
    }

    $destinationDirectory = Split-Path -Parent $Destination
    if (-not (Test-Path $destinationDirectory)) {
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    }

    Copy-Item -Path $Source -Destination $Destination -Force
    Write-Host "Exported $Description" -ForegroundColor Green
}

$documentsPath = [Environment]::GetFolderPath('MyDocuments')

# Windows Terminal settings
$windowsTerminalStable = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
$windowsTerminalPreview = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'
$windowsTerminalSource = if (Test-Path $windowsTerminalStable) { $windowsTerminalStable } elseif (Test-Path $windowsTerminalPreview) { $windowsTerminalPreview } else { $null }

Export-TerminalFile -Source $windowsTerminalSource -Destination (Join-Path $resolvedOutputRoot 'windows-terminal/settings.json') -Description 'Windows Terminal settings'

# PowerShell profiles
Export-TerminalFile -Source (Join-Path $documentsPath 'PowerShell\Microsoft.PowerShell_profile.ps1') -Destination (Join-Path $resolvedOutputRoot 'profiles/PowerShell/Microsoft.PowerShell_profile.ps1') -Description 'PowerShell 7 profile'
Export-TerminalFile -Source (Join-Path $documentsPath 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1') -Destination (Join-Path $resolvedOutputRoot 'profiles/WindowsPowerShell/Microsoft.PowerShell_profile.ps1') -Description 'Windows PowerShell 5.1 profile'

# Oh My Posh themes
$ohMyPoshSource = Join-Path $HOME '.config\oh-my-posh'
if (Test-Path $ohMyPoshSource) {
    $themeFiles = Get-ChildItem -Path $ohMyPoshSource -Filter '*.omp.json' -File -ErrorAction SilentlyContinue
    foreach ($themeFile in $themeFiles) {
        Export-TerminalFile -Source $themeFile.FullName -Destination (Join-Path $resolvedOutputRoot "oh-my-posh/$($themeFile.Name)") -Description "Oh My Posh theme $($themeFile.Name)"
    }
}
else {
    Write-Host 'Skipped Oh My Posh themes (folder not found).' -ForegroundColor Yellow
}

# PowerShell completions
$completionsSource = Join-Path $HOME '.config\powershell\completions'
if (Test-Path $completionsSource) {
    $completionFiles = Get-ChildItem -Path $completionsSource -Filter '*.ps1' -File -ErrorAction SilentlyContinue
    foreach ($completionFile in $completionFiles) {
        Export-TerminalFile -Source $completionFile.FullName -Destination (Join-Path $resolvedOutputRoot "completions/$($completionFile.Name)") -Description "completion script $($completionFile.Name)"
    }
}
else {
    Write-Host 'Skipped completions (folder not found).' -ForegroundColor Yellow
}

# fastfetch config
Export-TerminalFile -Source (Join-Path $env:APPDATA 'fastfetch\config.jsonc') -Destination (Join-Path $resolvedOutputRoot 'fastfetch/config.jsonc') -Description 'fastfetch config'

Write-Host "Terminal configuration exported to $resolvedOutputRoot" -ForegroundColor Green
