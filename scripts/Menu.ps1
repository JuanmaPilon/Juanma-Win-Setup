[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repoRoot 'modules/SetupHelpers.psm1') -Force

while ($true) {
    Write-Host ''
    Write-Host 'Choose an action:' -ForegroundColor Cyan
    Write-Host '1) Install Winget'
    Write-Host '2) Run full setup'
    Write-Host '3) Import environment variables'
    Write-Host '4) Import config backups'
    Write-Host '5) Export everything'
    Write-Host '6) Exit'

    $choice = Read-Host 'Selection'

    switch ($choice) {
        '1' {
            $runAsAdmin = Read-Host 'Install Winget as administrator? (y/n)'
            if ($runAsAdmin -match '^(y|yes)$') {
                $wingetScript = Join-Path $repoRoot 'scripts/Install-Winget.ps1'
                Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $wingetScript, '-RepositoryRoot', $repoRoot) | Out-Null
                Write-Host 'Started Winget installation in an elevated PowerShell window.' -ForegroundColor Green
            }
            else {
                & (Join-Path $repoRoot 'scripts/Install-Winget.ps1') -RepositoryRoot $repoRoot
            }
        }
        '2' {
            & (Join-Path $repoRoot 'Setup.ps1')
        }
        '3' {
            & (Join-Path $repoRoot 'scripts/Import-EnvironmentVariables.ps1')
        }
        '4' {
            & (Join-Path $repoRoot 'scripts/Import-Configs.ps1') -RepositoryRoot $repoRoot
        }
        '5' {
            & (Join-Path $repoRoot 'scripts/Export-EnvironmentVariables.ps1')
            & (Join-Path $repoRoot 'scripts/Export-StartAllBack.ps1')
            & (Join-Path $repoRoot 'scripts/Export-PowerToys.ps1')
            & (Join-Path $repoRoot 'scripts/Export-WindowsUI.ps1') -IncludeExplorerAdvanced -IncludeQuickAccessPins
            & (Join-Path $repoRoot 'scripts/Export-StartupApps.ps1')
            & (Join-Path $repoRoot 'scripts/Export-TerminalConfig.ps1')
            Write-Host 'Export completed for environment variables, StartAllBack, PowerToys, Windows UI, startup apps, and terminal.' -ForegroundColor Green
        }
        '6' {
            Write-SetupSuccess 'Exiting menu.'
            return
        }
        default {
            Write-Host 'Invalid selection.' -ForegroundColor Yellow
        }
    }
}
