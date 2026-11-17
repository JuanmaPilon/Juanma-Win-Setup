[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$TargetDisplay,
    [switch]$Restore
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDirectory = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$repoRoot = Split-Path -Parent $scriptDirectory
Import-Module (Join-Path $repoRoot 'modules/SetupHelpers.psm1') -Force

# Windows has no public "set primary display" API, but ChangeDisplaySettingsEx accepts
# CDS_SET_PRIMARY: the display placed at (0,0) with that flag becomes the primary one and
# Windows repositions the rest. Documented in wingdi.h; "The primary display device is
# always located at coordinates (0,0)".
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
        public const int DM_POSITION = 0x00000020;
        public const int DM_PELSWIDTH = 0x00080000;
        public const int DM_PELSHEIGHT = 0x00100000;
        public const int CDS_UPDATEREGISTRY = 0x00000001;
        public const int CDS_SET_PRIMARY = 0x00000010;
        public const int ENUM_CURRENT_SETTINGS = -1;

        [DllImport("user32.dll", EntryPoint = "EnumDisplaySettingsExA", CharSet = CharSet.Ansi, ExactSpelling = true)]
        public static extern bool EnumDisplaySettingsEx(string deviceName, int modeNum, ref DEVMODE devMode, int flags);

        [DllImport("user32.dll", EntryPoint = "ChangeDisplaySettingsExA", CharSet = CharSet.Ansi, ExactSpelling = true)]
        public static extern int ChangeDisplaySettingsEx(string deviceName, ref DEVMODE devMode, IntPtr hwnd, int flags, IntPtr lParam);
    }
}
'@

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
            Device = $name
            X      = $dm.dmPositionX
            Y      = $dm.dmPositionY
            Width  = $dm.dmPelsWidth
            Height = $dm.dmPelsHeight
        }
    }
    return $state
}

function Set-PrimaryDisplay {
    param([Parameter(Mandatory = $true)][string]$DeviceName)

    $dm = New-Object WinSetupDisplay.DEVMODE
    $dm.dmSize = [Int16][System.Runtime.InteropServices.Marshal]::SizeOf([type]'WinSetupDisplay.DEVMODE')
    if (-not [WinSetupDisplay.Display]::EnumDisplaySettingsEx($DeviceName, [WinSetupDisplay.Display]::ENUM_CURRENT_SETTINGS, [ref]$dm, 0)) {
        throw "No se pudo leer el modo actual de $DeviceName."
    }

    $dm.dmPositionX = 0
    $dm.dmPositionY = 0
    $dm.dmFields = $dm.dmFields -bor [WinSetupDisplay.Display]::DM_POSITION

    $flags = [WinSetupDisplay.Display]::CDS_UPDATEREGISTRY -bor [WinSetupDisplay.Display]::CDS_SET_PRIMARY
    return [WinSetupDisplay.Display]::ChangeDisplaySettingsEx($DeviceName, [ref]$dm, [IntPtr]::Zero, $flags, [IntPtr]::Zero)
}

# --- Estado actual -------------------------------------------------------------------
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
    Write-SetupError "No se encontró el monitor '$TargetDisplay'. Disponibles: $($deviceNames -join ', ')"
    return
}

if ($targetScreen.Primary -and -not $Restore) {
    # Picked the primary: switch to the other one instead, so it always toggles.
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

if ($DryRun) {
    Write-SetupWarning 'Dry run: no se cambia nada.'
    Write-SetupInfo ("Pasaría a principal: {0} (el actual es {1})" -f $targetScreen.DeviceName, $primaryScreen.DeviceName)
    Write-SetupSuccess 'Dry run completado.'
    return
}

$result = Set-PrimaryDisplay -DeviceName $targetScreen.DeviceName

if ($result -ne 0) {
    Write-SetupError "ChangeDisplaySettingsEx devolvió $result (0 = éxito). No se aplicó el cambio."
    switch ($result) {
        1 { Write-SetupWarning 'Windows pide reiniciar para aplicar el cambio.' }
        -2 { Write-SetupWarning 'El modo de video no es válido para ese monitor.' }
        -5 { Write-SetupWarning 'Parámetro inválido (BADPARAM).' }
        default { Write-SetupWarning 'Probá desde Configuración > Pantalla si se repite.' }
    }
    return
}

# Verify through the driver (Screen.AllScreens caches after the first access).
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

# Something went wrong: put the previous primary back before returning.
Write-SetupError 'El cambio no quedó como se esperaba; revirtiendo.'
if ($primaryScreen) {
    $revert = Set-PrimaryDisplay -DeviceName $primaryScreen.DeviceName
    if ($revert -eq 0) {
        Write-SetupWarning ("Se restauró {0} como principal." -f $primaryScreen.DeviceName)
    }
    else {
        Write-SetupError "No se pudo revertir (código $revert). Abrí Configuración > Pantalla y acomodá a mano."
    }
}
if ($overlap) { Write-SetupWarning 'Se detectaron monitores superpuestos.' }
