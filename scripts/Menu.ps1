[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repoRoot 'modules/SetupHelpers.psm1') -Force

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

function Invoke-ElevatedScript {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [string[]]$ScriptArguments = @(),
        [switch]$KeepOpen
    )

    $argumentList = @('-NoProfile', '-ExecutionPolicy', 'Bypass')
    if ($KeepOpen) { $argumentList += '-NoExit' }
    $argumentList += @('-File', $ScriptPath) + $ScriptArguments

    Start-Process powershell.exe -Verb RunAs -ArgumentList $argumentList | Out-Null
}

function Test-NeedsElevation {
    param([string]$Action)

    if ($isAdmin) { return $false }

    Write-SetupWarning "$Action necesita privilegios de administrador (registro HKLM, ProgramData y servicio de Windhawk)."
    $answer = Read-Host 'Ejecutar en una ventana elevada? (y/n)'
    return ($answer -match '^(y|yes|s|si)$')
}

function Show-MainMenu {
    Clear-Host
    Write-SetupBanner -Title 'WIN-SETUP' -Subtitle ("Repositorio: {0}" -f $repoRoot)
    Write-Host ''
    if ($isAdmin) {
        Write-SetupInfo 'Sesion: administrador'
    }
    else {
        Write-SetupInfo 'Sesion: usuario (algunas importaciones pediran elevacion)'
    }
    Write-Host ''

    Write-SetupMenuItem -Key '1' -Text 'Install Winget' -Hint 'bootstrap del gestor de paquetes'
    Write-SetupMenuItem -Key '2' -Text 'Run full setup' -Hint 'apps + configs + finalize'
    Write-SetupMenuItem -Key '3' -Text 'Import environment variables' -Hint 'variables de usuario/maquina'
    Write-SetupMenuItem -Key '4' -Text 'Import config backups' -Hint 'powertoys, windows-ui, terminal, windhawk...'
    Write-SetupMenuItem -Key '5' -Text 'Export everything' -Hint 'genera private-configs desde esta PC'
    Write-SetupMenuItem -Key '6' -Text 'Remove deprecated apps' -Hint 'desinstala lo que ya no se usa (winget-remove.txt)'
    Write-SetupMenuItem -Key '7' -Text 'Update all apps' -Hint 'winget upgrade --all'
    Write-SetupMenuItem -Key '0' -Text 'Exit'

    Write-Host ''
    Write-SetupRule
}

while ($true) {
    Show-MainMenu

    $choice = Read-Host 'Select'

    switch ($choice) {
        '1' {
            Write-Host ''
            $runAsAdmin = Read-Host 'Install Winget as administrator? (y/n)'
            if ($runAsAdmin -match '^(y|yes)$') {
                $wingetScript = Join-Path $repoRoot 'scripts/Install-Winget.ps1'
                Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $wingetScript, '-RepositoryRoot', $repoRoot) | Out-Null
                Write-SetupSuccess 'Started Winget installation in an elevated PowerShell window.'
            }
            else {
                & (Join-Path $repoRoot 'scripts/Install-Winget.ps1') -RepositoryRoot $repoRoot
            }
        }
        '2' {
            Write-Host ''
            Write-SetupRule
            if (Test-NeedsElevation -Action 'El setup completo') {
                Invoke-ElevatedScript -ScriptPath (Join-Path $repoRoot 'Setup.ps1') -KeepOpen
                Write-SetupSuccess 'Setup iniciado en una ventana elevada.'
            }
            else {
                & (Join-Path $repoRoot 'Setup.ps1')
            }
            Write-SetupRule
        }
        '3' {
            Write-Host ''
            Write-SetupRule
            & (Join-Path $repoRoot 'scripts/Import-EnvironmentVariables.ps1')
            Write-SetupRule
        }
        '4' {
            Write-Host ''
            Write-SetupRule
            if (Test-NeedsElevation -Action 'Importar los backups de configuracion') {
                Invoke-ElevatedScript -ScriptPath (Join-Path $repoRoot 'scripts/Import-Configs.ps1') -ScriptArguments @('-RepositoryRoot', $repoRoot) -KeepOpen
                Write-SetupSuccess 'Import iniciado en una ventana elevada.'
            }
            else {
                & (Join-Path $repoRoot 'scripts/Import-Configs.ps1') -RepositoryRoot $repoRoot
            }
            Write-SetupRule
        }
        '5' {
            Write-Host ''
            Write-SetupRule
            & (Join-Path $repoRoot 'scripts/Export-EnvironmentVariables.ps1')
            & (Join-Path $repoRoot 'scripts/Export-PowerToys.ps1')
            & (Join-Path $repoRoot 'scripts/Export-WindowsUI.ps1') -IncludeExplorerAdvanced -IncludeQuickAccessPins
            & (Join-Path $repoRoot 'scripts/Export-StartupApps.ps1')
            & (Join-Path $repoRoot 'scripts/Export-TerminalConfig.ps1')
            & (Join-Path $repoRoot 'scripts/Export-Windhawk.ps1')
            Write-SetupRule
            Write-SetupSuccess 'Export completed: environment variables, PowerToys, Windows UI, startup apps, terminal and Windhawk.'
        }
        '6' {
            Write-Host ''
            Write-SetupRule
            & (Join-Path $repoRoot 'scripts/Remove-DeprecatedApps.ps1') -RepositoryRoot $repoRoot
            Write-SetupRule
        }
        '7' {
            Write-Host ''
            Write-SetupRule
            & (Join-Path $repoRoot 'scripts/Update-Apps.ps1') -RepositoryRoot $repoRoot
            Write-SetupRule
        }
        '0' {
            Write-Host ''
            Write-SetupSuccess 'Exiting menu.'
            return
        }
        default {
            Write-SetupWarning 'Invalid selection.'
        }
    }

    Write-Host ''
    Write-Host '  Press Enter to return to the menu...' -ForegroundColor DarkGray -NoNewline
    $null = Read-Host
}
