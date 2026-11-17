[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$TargetDisplay,
    [switch]$ShowErrors
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDirectory = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$repoRoot = Split-Path -Parent $scriptDirectory
Import-Module (Join-Path $repoRoot 'modules/SetupHelpers.psm1') -Force

# Why MultiMonitorTool and not ChangeDisplaySettingsEx: Windows 11 rejects CDS_NORESET with
# DISP_CHANGE_BADFLAGS, and without that batch the legacy API repositions a display but never
# hands over "primary" (the display at (0,0)). This tool goes through SetDisplayConfig, which
# does. Syntax verified against the readme.txt shipped in its own zip: /SetMonitors with
# Primary=1 plus PositionX/PositionY, one quoted block per monitor.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace WinSetupDisplay
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DEVMODE
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public int dmDisplayOrientation;
        public int dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel;
        public int dmPelsWidth;
        public int dmPelsHeight;
        public int dmDisplayFlags;
        public int dmDisplayFrequency;
        public int dmICMMethod;
        public int dmICMIntent;
        public int dmMediaType;
        public int dmDitherType;
        public int dmReserved1;
        public int dmReserved2;
        public int dmPanningWidth;
        public int dmPanningHeight;
    }

    public static class Display
    {
        public const int ENUM_CURRENT_SETTINGS = -1;

        [DllImport("user32.dll", EntryPoint = "EnumDisplaySettingsExA", CharSet = CharSet.Ansi, ExactSpelling = true)]
        public static extern bool EnumDisplaySettingsEx(string deviceName, int modeNum, ref DEVMODE devMode, int flags);
    }
}
'@

function Show-Failure {
    param([string]$Message)

    Write-SetupError $Message
    if ($ShowErrors) {
        [void][System.Windows.Forms.MessageBox]::Show($Message, 'Cambiar pantalla principal', 'OK', 'Warning')
    }
}

function Get-DisplayState {
    param([string[]]$DeviceNames)

    $state = @()
    foreach ($name in $DeviceNames) {
        $dm = New-Object WinSetupDisplay.DEVMODE
        $dm.dmSize = [Int16][System.Runtime.InteropServices.Marshal]::SizeOf([type]'WinSetupDisplay.DEVMODE')
        if (-not [WinSetupDisplay.Display]::EnumDisplaySettingsEx($name, [WinSetupDisplay.Display]::ENUM_CURRENT_SETTINGS, [ref]$dm, 0)) {
            continue
        }
        $state += [pscustomobject]@{
            Device      = $name
            X           = $dm.dmPositionX
            Y           = $dm.dmPositionY
            Width       = $dm.dmPelsWidth
            Height      = $dm.dmPelsHeight
            BitsPerPel  = $dm.dmBitsPerPel
            Frequency   = $dm.dmDisplayFrequency
            Orientation = $dm.dmDisplayOrientation
        }
    }
    return $state
}

# --- Tool ----------------------------------------------------------------------------
$toolCandidates = @(
    (Join-Path $repoRoot 'tools\MultiMonitorTool.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\MultiMonitorTool\MultiMonitorTool.exe')
)
$tool = $toolCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $tool) {
    Show-Failure ("MultiMonitorTool.exe no está instalado.`n`nDescargalo de https://www.nirsoft.net/utils/multimonitortool-x64.html y extraelo en %LOCALAPPDATA%\Programs\MultiMonitorTool.")
    return
}

# --- Current layout ------------------------------------------------------------------
Add-Type -AssemblyName System.Windows.Forms
$screens = @([System.Windows.Forms.Screen]::AllScreens)
$deviceNames = @($screens | ForEach-Object { $_.DeviceName })

if ($deviceNames.Count -lt 2) {
    Write-SetupWarning 'Sólo hay un monitor conectado: no hay nada para alternar.'
    return
}

$primaryScreen = $screens | Where-Object Primary | Select-Object -First 1

if ([string]::IsNullOrWhiteSpace($TargetDisplay)) {
    $targetScreen = $screens | Where-Object { -not $_.Primary } | Select-Object -First 1
}
else {
    $targetScreen = $screens | Where-Object { $_.DeviceName -eq $TargetDisplay } | Select-Object -First 1
}

if (-not $targetScreen) {
    Show-Failure "No se encontró el monitor '$TargetDisplay'. Disponibles: $($deviceNames -join ', ')"
    return
}

if ($targetScreen.Primary) {
    # Picked the primary: switch to the other one instead, so the shortcut always toggles.
    $targetScreen = $screens | Where-Object { -not $_.Primary } | Select-Object -First 1
    if (-not $targetScreen) {
        Write-SetupWarning 'No hay otro monitor para convertir en principal.'
        return
    }
}

$before = Get-DisplayState -DeviceNames $deviceNames

Write-SetupStep 'Monitores detectados'
foreach ($display in $before) {
    $isPrimary = $display.X -eq 0 -and $display.Y -eq 0
    Write-SetupInfo ("  {0}: {1}x{2} en ({3},{4}){5}" -f $display.Device, $display.Width, $display.Height, $display.X, $display.Y, $(if ($isPrimary) { '  <- principal' } else { '' }))
}

# --- Build the new arrangement -------------------------------------------------------
# The target goes to (0,0) as primary and the others are laid out around it keeping the
# physical left-to-right order. Deriving the side from the raw X sign does not work: after
# one swap the target already sits at (0,0), so nothing is negative anymore and the next
# toggle would move the secondary to the wrong side.
$targetState = $before | Where-Object { $_.Device -eq $targetScreen.DeviceName } | Select-Object -First 1

$ordered = @($before | Sort-Object -Property X, Y)
$targetIndex = -1
for ($i = 0; $i -lt $ordered.Count; $i++) {
    if ($ordered[$i].Device -eq $targetScreen.DeviceName) { $targetIndex = $i; break }
}

$newX = @{}
$newX[$ordered[$targetIndex].Device] = 0

$cursor = 0
for ($i = $targetIndex - 1; $i -ge 0; $i--) {
    $cursor -= $ordered[$i].Width
    $newX[$ordered[$i].Device] = $cursor
}

$cursor = $ordered[$targetIndex].Width
for ($i = $targetIndex + 1; $i -lt $ordered.Count; $i++) {
    $newX[$ordered[$i].Device] = $cursor
    $cursor += $ordered[$i].Width
}

$entries = @()
foreach ($display in $before) {
    $isTarget = $display.Device -eq $targetScreen.DeviceName
    $frequency = if ($display.Frequency -le 1) { 60 } else { $display.Frequency }
    $entries += 'Name={0} Primary={1} BitsPerPixel={2} Width={3} Height={4} DisplayFlags=0 DisplayFrequency={5} DisplayOrientation={6} PositionX={7} PositionY=0' -f `
        $display.Device, $(if ($isTarget) { 1 } else { 0 }), $display.BitsPerPel, $display.Width, $display.Height, $frequency, $display.Orientation, $newX[$display.Device]
}

if ($DryRun) {
    Write-SetupWarning 'Dry run: no se cambia nada.'
    Write-SetupInfo ("Pasaría a principal: {0} (el actual es {1})" -f $targetScreen.DeviceName, $primaryScreen.DeviceName)
    foreach ($entry in $entries) { Write-SetupInfo "  /SetMonitors `"$entry`"" }
    Write-SetupSuccess 'Dry run completado.'
    return
}

Write-SetupStep ("Aplicando: {0} queda como principal" -f $targetScreen.DeviceName)
$toolArgs = @('/SetMonitors') + $entries
$output = & $tool @toolArgs 2>&1 | Out-String
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    Show-Failure "MultiMonitorTool devolvió el código $exitCode.`n$($output.Trim())"
    return
}

Start-Sleep -Milliseconds 700

# --- Verify through the driver (Screen.AllScreens caches after first access) ---------
$after = Get-DisplayState -DeviceNames $deviceNames
$newPrimary = $after | Where-Object { $_.X -eq 0 -and $_.Y -eq 0 } | Select-Object -First 1

$overlap = $false
for ($i = 0; $i -lt $after.Count; $i++) {
    for ($j = $i + 1; $j -lt $after.Count; $j++) {
        $a = $after[$i]; $b = $after[$j]
        if ($a.X -lt ($b.X + $b.Width) -and $b.X -lt ($a.X + $a.Width) -and
            $a.Y -lt ($b.Y + $b.Height) -and $b.Y -lt ($a.Y + $a.Height)) {
            $overlap = $true
        }
    }
}

if ($newPrimary -and $newPrimary.Device -eq $targetScreen.DeviceName -and -not $overlap) {
    Write-SetupSuccess ("Ahora el principal es {0}." -f $newPrimary.Device)
    foreach ($display in $after) {
        Write-SetupInfo ("  {0}: en ({1},{2})" -f $display.Device, $display.X, $display.Y)
    }
    return
}

$reason = if ($overlap) { 'quedaron monitores superpuestos' } else { 'Windows no cambió el principal' }
Show-Failure "El cambio no quedó como se esperaba ($reason). Probá desde Configuración > Pantalla."
