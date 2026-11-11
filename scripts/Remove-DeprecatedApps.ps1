[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [switch]$DryRun,
    [switch]$AllowInteractiveFallback
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Import-Module (Join-Path $RepositoryRoot 'modules/SetupHelpers.psm1') -Force

Write-SetupStep 'Checking for deprecated applications'

$manifestPath = Join-Path $RepositoryRoot 'apps/winget-remove.txt'
if (-not (Test-Path $manifestPath)) {
    Write-SetupInfo 'No apps/winget-remove.txt found; skipping cleanup stage.'
    return
}

# Format: PackageId | optional DisplayName pattern | optional extra silent args
$packages = @()
foreach ($rawLine in Get-Content $manifestPath) {
    $line = $rawLine.Trim()
    if (-not $line -or $line.StartsWith('#')) { continue }
    $parts = @($line -split '\|' | ForEach-Object { $_.Trim() })
    $packages += [pscustomobject]@{
        Id          = $parts[0]
        NamePattern = if ($parts.Count -gt 1 -and $parts[1]) { $parts[1] } else { $null }
        SilentArgs  = if ($parts.Count -gt 2 -and $parts[2]) { $parts[2] } else { $null }
    }
}

if ($packages.Count -eq 0) {
    Write-SetupInfo 'Deprecated apps list is empty; nothing to remove.'
    return
}

try {
    $wingetPath = Initialize-Winget
    Write-SetupInfo "Winget: $wingetPath"
}
catch {
    Write-SetupWarning "Winget is not available; cannot check deprecated apps. $($_.Exception.Message)"
    return
}

function Test-PackageInstalled {
    param([Parameter(Mandatory = $true)][string]$PackageId)

    $listOutput = winget list --id $PackageId --exact --source winget 2>$null | Out-String
    if ($LASTEXITCODE -ne 0) { return $false }
    return ($listOutput -match [regex]::Escape($PackageId))
}

function Get-UninstallEntry {
    param(
        [Parameter(Mandatory = $true)][string]$PackageId,
        [string]$NamePattern
    )

    # "Publisher.Product" -> "Product" -> "Product with spaces"
    $shortName = ($PackageId -split '\.')[-1]
    $searchName = if ($NamePattern) { $NamePattern } else { ($shortName -replace '[-_]', ' ').Trim() }

    $registryRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $candidates = @()
    foreach ($root in $registryRoots) {
        $candidates += Get-ItemProperty $root -ErrorAction SilentlyContinue |
            Where-Object { $_.PSObject.Properties.Name -contains 'DisplayName' -and $_.DisplayName }
    }

    $exact = $candidates | Where-Object {
        ($_.DisplayName -replace '\s', '') -ieq ($searchName -replace '\s', '')
    } | Select-Object -First 1

    if ($exact) { return $exact }

    return $candidates | Where-Object { $_.DisplayName -like "*$searchName*" } | Select-Object -First 1
}

function Stop-TargetProcesses {
    param([string]$InstallLocation, [string[]]$NameHints)

    $killed = @()
    foreach ($process in Get-Process -ErrorAction SilentlyContinue) {
        $shouldStop = $false

        if ($InstallLocation -and $process.Path -and $process.Path.StartsWith($InstallLocation, [System.StringComparison]::OrdinalIgnoreCase)) {
            $shouldStop = $true
        }
        elseif ($NameHints.Count -gt 0 -and ($NameHints -icontains $process.ProcessName)) {
            $shouldStop = $true
        }

        if (-not $shouldStop) { continue }

        try {
            Stop-Process -Id $process.Id -Force -ErrorAction Stop
            $killed += $process.ProcessName
        }
        catch { }
    }

    if ($killed.Count -gt 0) {
        Write-SetupInfo "Closed running process(es): $((($killed | Select-Object -Unique) -join ', '))"
        Start-Sleep -Milliseconds 600
    }
}

function Get-SilentUninstallCommand {
    <#
        Returns @{ File; Arguments } for a silent uninstall, or $null when the entry has
        no usable uninstall command.
    #>
    param(
        [Parameter(Mandatory = $true)]$Entry,
        [string]$ExtraSilentArgs
    )

    $quietString = if ($Entry.PSObject.Properties.Name -contains 'QuietUninstallString') { $Entry.QuietUninstallString } else { $null }
    $uninstallString = if ($Entry.PSObject.Properties.Name -contains 'UninstallString') { $Entry.UninstallString } else { $null }

    $command = if ($quietString) { $quietString } else { $uninstallString }
    if (-not $command) { return $null }

    # MSI product code
    if ($command -match '(?i)msiexec(?:\.exe)?["'']?\s*(?:/x|/uninstall|-x)?\s*(\{[0-9A-Fa-f\-]+\})') {
        return @{ File = 'msiexec.exe'; Arguments = "/x $($Matches[1]) /qn /norestart" }
    }

    # Split executable from arguments (handles quoted paths with spaces)
    if ($command -match '^\s*"([^"]+)"\s*(.*)$') {
        $exe = $Matches[1]
        $rest = $Matches[2]
    }
    elseif ($command -match '^\s*(\S+)\s*(.*)$') {
        $exe = $Matches[1]
        $rest = $Matches[2]
    }
    else {
        return $null
    }

    # Squirrel (Update.exe)
    if ([System.IO.Path]::GetFileName($exe) -ieq 'Update.exe') {
        return @{ File = $exe; Arguments = '--uninstall --silent' }
    }

    # Firefox-based uninstaller (Zen Browser ships uninstall\helper.exe)
    if ($exe -match '(?i)\\uninstall\\helper\.exe$') {
        return @{ File = $exe; Arguments = '-ms' }
    }

    $silent = if ($ExtraSilentArgs) { $ExtraSilentArgs } else { '/S' }
    return @{ File = $exe; Arguments = ("$rest $silent").Trim() }
}

function Invoke-SilentUninstall {
    param(
        [Parameter(Mandatory = $true)]$Command,
        [int]$TimeoutSeconds = 180
    )

    try {
        $process = Start-Process -FilePath $Command.File -ArgumentList $Command.Arguments -PassThru -ErrorAction Stop
    }
    catch {
        Write-SetupWarning "Could not start uninstaller '$($Command.File)': $($_.Exception.Message)"
        return $false
    }

    try {
        $process | Wait-Process -Timeout $TimeoutSeconds -ErrorAction Stop
        return $true
    }
    catch {
        Write-SetupWarning "Uninstaller did not finish within $TimeoutSeconds seconds; it is probably waiting for user input."
        return $false
    }
}

$summary = [ordered]@{
    Removed     = @()
    WouldRemove = @()
    NotPresent  = @()
    Manual      = @()
}

$total = $packages.Count
$index = 0

foreach ($package in $packages) {
    $index++
    $packageId = $package.Id
    Write-SetupProgress -Activity 'Removing deprecated applications' -Status "$packageId ($index/$total)" -PercentComplete ([int](($index - 1) * 100 / [Math]::Max($total, 1)))

    if (-not (Test-PackageInstalled -PackageId $packageId)) {
        Write-SetupInfo "Not installed, nothing to do: $packageId"
        $summary.NotPresent += $packageId
        continue
    }

    if ($DryRun) {
        Write-SetupWarning "Would uninstall deprecated package: $packageId"
        $summary.WouldRemove += $packageId
        continue
    }

    $entry = Get-UninstallEntry -PackageId $packageId -NamePattern $package.NamePattern
    $displayName = if ($entry) { $entry.DisplayName } else { $packageId }
    $installLocation = if ($entry -and $entry.PSObject.Properties.Name -contains 'InstallLocation') { $entry.InstallLocation } else { $null }

    Write-SetupStep "Uninstalling deprecated package: $displayName"

    # A running app makes most uninstallers show a modal "close the app first" dialog
    $nameHint = (($packageId -split '\.')[-1] -replace '[-_]', '')
    Stop-TargetProcesses -InstallLocation $installLocation -NameHints @($nameHint)

    # Attempt 1: Winget, silent and non-interactive
    $wingetOutput = winget uninstall --id $packageId --exact --silent --disable-interactivity --accept-source-agreements 2>&1 | Out-String
    $wingetExit = $LASTEXITCODE

    if ($wingetExit -eq 0 -and -not (Test-PackageInstalled -PackageId $packageId)) {
        Write-SetupSuccess "Removed deprecated package: $displayName"
        $summary.Removed += $packageId
        continue
    }

    # Attempt 2: call the uninstaller ourselves with its own silent switches
    if ($entry) {
        $silentCommand = Get-SilentUninstallCommand -Entry $entry -ExtraSilentArgs $package.SilentArgs
        if ($silentCommand) {
            Write-SetupInfo "Winget could not remove it silently; running: $($silentCommand.File) $($silentCommand.Arguments)"
            $null = Invoke-SilentUninstall -Command $silentCommand
            if (-not (Test-PackageInstalled -PackageId $packageId)) {
                Write-SetupSuccess "Removed deprecated package: $displayName (direct silent uninstall)"
                $summary.Removed += $packageId
                continue
            }
        }
    }

    Write-SetupWarning "Could not remove '$displayName' without interaction (winget exit code $wingetExit)."
    foreach ($line in @($wingetOutput -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 3)) {
        Write-SetupWarning "  $($line.Trim())"
    }

    # Attempt 3 (opt-in): let the vendor uninstaller run interactively
    if ($AllowInteractiveFallback -and $entry) {
        Write-SetupInfo "Launching the interactive uninstaller for '$displayName'..."
        $interactiveCommand = Get-SilentUninstallCommand -Entry ([pscustomobject]@{
                UninstallString      = if ($entry.PSObject.Properties.Name -contains 'UninstallString') { $entry.UninstallString } else { $null }
                QuietUninstallString = $null
            }) -ExtraSilentArgs ''
        if ($interactiveCommand) {
            try {
                Start-Process -FilePath $interactiveCommand.File -ArgumentList $interactiveCommand.Arguments -Wait -ErrorAction Stop
                if (-not (Test-PackageInstalled -PackageId $packageId)) {
                    Write-SetupSuccess "Removed deprecated package: $displayName (interactive)"
                    $summary.Removed += $packageId
                    continue
                }
            }
            catch {
                Write-SetupWarning "Interactive uninstall failed: $($_.Exception.Message)"
            }
        }
    }

    $summary.Manual += $displayName
}

Clear-SetupProgress

Write-SetupStep "Cleanup summary: removed $($summary.Removed.Count); would remove $($summary.WouldRemove.Count); not present $($summary.NotPresent.Count); manual $($summary.Manual.Count)"

if ($summary.Removed.Count -gt 0) {
    Write-SetupInfo "Removed during this run: $($summary.Removed -join ', ')"
}
if ($summary.WouldRemove.Count -gt 0) {
    Write-SetupInfo "Would remove in dry-run: $($summary.WouldRemove -join ', ')"
}
if ($summary.Manual.Count -gt 0) {
    Write-SetupWarning "Needs manual removal: $($summary.Manual -join ', ')"
    Write-SetupWarning 'Those uninstallers do not support a silent switch. Remove them from Settings > Apps, or re-run with -AllowInteractiveFallback.'
}

Write-SetupStep 'Cleanup stage completed.'
