function Write-SetupStep {
    param([Parameter(Mandatory = $true)][string]$Message)

    Write-Host "[setup] $Message" -ForegroundColor DarkCyan
}

function Write-SetupInfo {
    param([Parameter(Mandatory = $true)][string]$Message)

    Write-Host "[setup] $Message" -ForegroundColor Gray
}

function Write-SetupSuccess {
    param([Parameter(Mandatory = $true)][string]$Message)

    Write-Host "[setup] $Message" -ForegroundColor Green
}

function Write-SetupWarning {
    param([Parameter(Mandatory = $true)][string]$Message)

    Write-Host "[setup] $Message" -ForegroundColor Yellow
}

function Write-SetupError {
    param([Parameter(Mandatory = $true)][string]$Message)

    Write-Host "[setup] $Message" -ForegroundColor Red
}

function Test-CommandAvailable {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name is required but was not found on PATH."
    }
}

function Get-WingetCommandPath {
    $commandPath = Get-Command winget -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue
    if ($commandPath -and (Test-Path $commandPath)) {
        return $commandPath
    }

    $localWindowsAppsPath = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path $localWindowsAppsPath) {
        return $localWindowsAppsPath
    }

    $windowsAppsRoot = Join-Path $env:ProgramFiles 'WindowsApps'
    if (Test-Path $windowsAppsRoot) {
        $foundPath = Get-ChildItem -Path $windowsAppsRoot -Filter 'winget.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
        if ($foundPath) {
            return $foundPath
        }
    }

    return $null
}

function Initialize-Winget {
    $wingetPath = Get-WingetCommandPath
    if ($wingetPath) {
        $wingetDirectory = Split-Path -Parent $wingetPath
        if (-not ($env:Path -split ';' | Where-Object { $_ -eq $wingetDirectory })) {
            $env:Path = "$env:Path;$wingetDirectory"
        }

        return $wingetPath
    }

    Write-SetupStep 'Winget was not found. Attempting to bootstrap it automatically.'

    try {
        $progressPreference = 'SilentlyContinue'
        Install-PackageProvider -Name NuGet -Force | Out-Null
        Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery -Scope CurrentUser | Out-Null

        Import-Module Microsoft.WinGet.Client -Force -ErrorAction Stop
        Repair-WinGetPackageManager -AllUsers -Force
    }
    catch {
        Write-SetupStep 'The Microsoft.WinGet.Client repair path did not succeed; trying the official installer.'
    }

    $wingetPath = Get-WingetCommandPath
    if ($wingetPath) {
        $wingetDirectory = Split-Path -Parent $wingetPath
        if (-not ($env:Path -split ';' | Where-Object { $_ -eq $wingetDirectory })) {
            $env:Path = "$env:Path;$wingetDirectory"
        }

        return $wingetPath
    }

    $tempDir = Join-Path $env:TEMP 'winget-bootstrap'
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    $installerPath = Join-Path $tempDir 'Microsoft.DesktopAppInstaller.exe'
    $installerUrl = 'https://aka.ms/getwinget'

    try {
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -ErrorAction Stop
        $process = Start-Process -FilePath $installerPath -ArgumentList '/silent', '/install', '/passive' -Wait -PassThru -NoNewWindow

        if ($process -and $process.ExitCode -ne 0) {
            throw "The official Winget installer exited with code $($process.ExitCode)."
        }
    }
    catch {
        throw "Winget could not be bootstrapped automatically. Install it manually or repair the package manager first. $($_.Exception.Message)"
    }

    $wingetPath = Get-WingetCommandPath
    if (-not $wingetPath) {
        throw 'Winget is still unavailable after the bootstrap attempt.'
    }

    $wingetDirectory = Split-Path -Parent $wingetPath
    if (-not ($env:Path -split ';' | Where-Object { $_ -eq $wingetDirectory })) {
        $env:Path = "$env:Path;$wingetDirectory"
    }

    return $wingetPath
}

function Import-RegistryGroup {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if (-not (Test-Path $Path)) {
        Write-SetupStep "No registry file found for $Name"
        return
    }

    Write-SetupStep "Importing registry group: $Name"
    reg import $Path | Out-Null
}

function Write-SetupBanner {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [string]$Subtitle
    )

    $width = 62
    $line = [string]::new([char]0x2550, $width)
    $side = [char]0x2551
    $empty = [string]::new(' ', $width)

    Write-Host ([string][char]0x2554 + $line + [string][char]0x2557) -ForegroundColor DarkCyan
    Write-Host ($side + $empty + $side) -ForegroundColor DarkCyan
    Write-Host ($side + ("  {0}" -f $Title).PadRight($width) + $side) -ForegroundColor Cyan
    if ($Subtitle) {
        Write-Host ($side + ("  {0}" -f $Subtitle).PadRight($width) + $side) -ForegroundColor DarkGray
    }
    Write-Host ($side + $empty + $side) -ForegroundColor DarkCyan
    Write-Host ([string][char]0x255A + $line + [string][char]0x255D) -ForegroundColor DarkCyan
}

function Write-SetupRule {
    param([int]$Width = 62)

    Write-Host ([string]::new([char]0x2500, $Width)) -ForegroundColor DarkGray
}

function Write-SetupMenuItem {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Text,
        [string]$Hint
    )

    Write-Host '  [' -NoNewline -ForegroundColor DarkGray
    Write-Host $Key -NoNewline -ForegroundColor Cyan
    Write-Host ']  ' -NoNewline -ForegroundColor DarkGray
    Write-Host $Text -NoNewline -ForegroundColor White
    if ($Hint) {
        Write-Host "   $Hint" -ForegroundColor DarkGray
    }
    else {
        Write-Host ''
    }
}

function Write-SetupProgress {
    param(
        [Parameter(Mandatory = $true)][string]$Activity,
        [string]$Status,
        [int]$PercentComplete = -1,
        [int]$Id = 1
    )

    $params = @{ Id = $Id; Activity = $Activity }
    if ($PSBoundParameters.ContainsKey('Status')) { $params['Status'] = $Status }
    if ($PercentComplete -ge 0) { $params['PercentComplete'] = [Math]::Min($PercentComplete, 100) }
    Write-Progress @params
}

function Clear-SetupProgress {
    param([int]$Id = 1)

    Write-Progress -Id $Id -Activity ' ' -Completed
}

Export-ModuleMember -Function Write-SetupStep, Write-SetupInfo, Write-SetupSuccess, Write-SetupWarning, Write-SetupError, Write-SetupBanner, Write-SetupRule, Write-SetupMenuItem, Write-SetupProgress, Clear-SetupProgress, Test-CommandAvailable, Initialize-Winget, Import-RegistryGroup
