[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$TargetDisplay,
    [switch]$Restore,
    [switch]$ShowErrors,
    [switch]$Diagnose
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
        public const int CDS_NORESET = 0x10000000;
        public const int ENUM_CURRENT_SETTINGS = -1;

        [DllImport("user32.dll", EntryPoint = "EnumDisplaySettingsExA", CharSet = CharSet.Ansi, ExactSpelling = true)]
        public static extern bool EnumDisplaySettingsEx(string deviceName, int modeNum, ref DEVMODE devMode, int flags);

        [DllImport("user32.dll", EntryPoint = "ChangeDisplaySettingsExA", CharSet = CharSet.Ansi, ExactSpelling = true)]
        public static extern int ChangeDisplaySettingsEx(string deviceName, ref DEVMODE devMode, IntPtr hwnd, int flags, IntPtr lParam);

        // Commits a CDS_NORESET batch: deviceName and devMode are NULL on purpose.
        [DllImport("user32.dll", EntryPoint = "ChangeDisplaySettingsExA", CharSet = CharSet.Ansi, ExactSpelling = true)]
        public static extern int ChangeDisplaySettingsExCommit(string deviceName, IntPtr devMode, IntPtr hwnd, int flags, IntPtr lParam);
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

function Set-DisplayLayout {
    <#
        Applies a full set of positions in one batch and commits it. Windows only accepts a
        primary change when the whole arrangement arrives together: CDS_SET_PRIMARY on its own
        just repositions the display and the system puts it back in the first free slot.
        The list is applied in order, so the new primary (0,0) must come first: moving the old
        primary off (0,0) before the new one is there makes the whole batch invalid.
    #>
    param([Parameter(Mandatory = $true)][object[]]$Layout)

    $problems = @()
    foreach ($entry in $Layout) {
        $dm = New-Object WinSetupDisplay.DEVMODE
        $dm.dmSize = [Int16][System.Runtime.InteropServices.Marshal]::SizeOf([type]'WinSetupDisplay.DEVMODE')
        if (-not [WinSetupDisplay.Display]::EnumDisplaySettingsEx($entry.Device, [WinSetupDisplay.Display]::ENUM_CURRENT_SETTINGS, [ref]$dm, 0)) {
            $problems += "$($entry.Device) (no se pudo leer su modo actual)"
            continue
        }

        $dm.dmPositionX = $entry.X
        $dm.dmPositionY = $entry.Y
        $dm.dmFields = $dm.dmFields -bor [WinSetupDisplay.Display]::DM_POSITION

        $flags = [WinSetupDisplay.Display]::CDS_NORESET -bor [WinSetupDisplay.Display]::CDS_UPDATEREGISTRY
        $rc = [WinSetupDisplay.Display]::ChangeDisplaySettingsEx($entry.Device, [ref]$dm, [IntPtr]::Zero, $flags, [IntPtr]::Zero)
        if ($rc -ne 0) { $problems += "$($entry.Device) (código $rc)" }
    }

    $commit = [WinSetupDisplay.Display]::ChangeDisplaySettingsExCommit($null, [IntPtr]::Zero, [IntPtr]::Zero, 0, [IntPtr]::Zero)
    return [pscustomobject]@{ Commit = $commit; Problems = $problems }
}

function Set-PrimaryDisplay {
    <#
        Documented combination for changing the primary: place the display at (0,0), ask for
        CDS_SET_PRIMARY inside a CDS_NORESET batch and commit. Windows then rearranges the rest
        of the displays by itself.
    #>
    param([Parameter(Mandatory = $true)][string]$DeviceName)

    $dm = New-Object WinSetupDisplay.DEVMODE
    $dm.dmSize = [Int16][System.Runtime.InteropServices.Marshal]::SizeOf([type]'WinSetupDisplay.DEVMODE')
    if (-not [WinSetupDisplay.Display]::EnumDisplaySettingsEx($DeviceName, [WinSetupDisplay.Display]::ENUM_CURRENT_SETTINGS, [ref]$dm, 0)) {
        return [pscustomobject]@{ Ok = $false; Detail = 'no se pudo leer el modo actual'; Code = -1; Commit = -1 }
    }

    $dm.dmPositionX = 0
    $dm.dmPositionY = 0
    $dm.dmFields = $dm.dmFields -bor [WinSetupDisplay.Display]::DM_POSITION

    $flags = [WinSetupDisplay.Display]::CDS_SET_PRIMARY -bor [WinSetupDisplay.Display]::CDS_UPDATEREGISTRY -bor [WinSetupDisplay.Display]::CDS_NORESET
    $rc = [WinSetupDisplay.Display]::ChangeDisplaySettingsEx($DeviceName, [ref]$dm, [IntPtr]::Zero, $flags, [IntPtr]::Zero)
    $commit = [WinSetupDisplay.Display]::ChangeDisplaySettingsExCommit($null, [IntPtr]::Zero, [IntPtr]::Zero, 0, [IntPtr]::Zero)

    $ok = ($rc -eq 0 -and $commit -eq 0)
    return [pscustomobject]@{ Ok = $ok; Detail = ''; Code = $rc; Commit = $commit }
}

function Show-Failure {
    param([string]$Message)

    Write-SetupError $Message
    if ($ShowErrors) {
        [void][System.Windows.Forms.MessageBox]::Show($Message, 'Cambiar pantalla principal', 'OK', 'Warning')
    }
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

if ($Diagnose) {
    Write-SetupStep 'Diagnóstico'
    Write-SetupInfo ("sizeof(DEVMODE) = {0} (esperado 156)" -f [System.Runtime.InteropServices.Marshal]::SizeOf([type]'WinSetupDisplay.DEVMODE'))
    foreach ($display in $before) {
        # A: apply the identical mode, no flags. Proves the DEVMODE is accepted.
        $dmA = New-Object WinSetupDisplay.DEVMODE
        $dmA.dmSize = [Int16][System.Runtime.InteropServices.Marshal]::SizeOf([type]'WinSetupDisplay.DEVMODE')
        $null = [WinSetupDisplay.Display]::EnumDisplaySettingsEx($display.Device, [WinSetupDisplay.Display]::ENUM_CURRENT_SETTINGS, [ref]$dmA, 0)
        $rcA = [WinSetupDisplay.Display]::ChangeDisplaySettingsEx($display.Device, [ref]$dmA, [IntPtr]::Zero, 0, [IntPtr]::Zero)

        # B: same mode + CDS_TEST. Validates without applying.
        $rcB = [WinSetupDisplay.Display]::ChangeDisplaySettingsEx($display.Device, [ref]$dmA, [IntPtr]::Zero, 2, [IntPtr]::Zero)

        # C: only the position field marked as changed, same values.
        $dmC = $dmA
        $dmC.dmFields = [WinSetupDisplay.Display]::DM_POSITION
        $rcC = [WinSetupDisplay.Display]::ChangeDisplaySettingsEx($display.Device, [ref]$dmC, [IntPtr]::Zero, 2, [IntPtr]::Zero)

        Write-SetupInfo ("  {0}: modo actual={1}, test modo={2}, test solo-posición={3}" -f $display.Device, $rcA, $rcB, $rcC)

        # D/E: which CDS_NORESET combinations does this driver accept?
        $dmD = $dmA
        $dmD.dmFields = [WinSetupDisplay.Display]::DM_POSITION
        $rcD = [WinSetupDisplay.Display]::ChangeDisplaySettingsEx($display.Device, [ref]$dmD, [IntPtr]::Zero, [WinSetupDisplay.Display]::CDS_NORESET, [IntPtr]::Zero)

        $dmE = $dmA
        $dmE.dmFields = [WinSetupDisplay.Display]::DM_POSITION
        $flagsE = [WinSetupDisplay.Display]::CDS_NORESET -bor [WinSetupDisplay.Display]::CDS_SET_PRIMARY
        $rcE = [WinSetupDisplay.Display]::ChangeDisplaySettingsEx($display.Device, [ref]$dmE, [IntPtr]::Zero, $flagsE, [IntPtr]::Zero)

        Write-SetupInfo ("      NORESET={0}  NORESET+SET_PRIMARY={1}" -f $rcD, $rcE)
    }
    $commitRc = [WinSetupDisplay.Display]::ChangeDisplaySettingsExCommit($null, [IntPtr]::Zero, [IntPtr]::Zero, 0, [IntPtr]::Zero)
    Write-SetupInfo ("      commit del lote = {0}" -f $commitRc)
    Write-SetupWarning 'Códigos: 0 = éxito, -1 = FAILED (driver rechaza), -5 = BADPARAM (flags/estructura).'
    return
}

if ($DryRun) {
    Write-SetupWarning 'Dry run: no se cambia nada.'
    Write-SetupInfo ("Pasaría a principal: {0} (el actual es {1})" -f $targetScreen.DeviceName, $primaryScreen.DeviceName)
    Write-SetupSuccess 'Dry run completado.'
    return
}

# New arrangement: the target goes to (0,0) and the rest keep their side, so the
# physical layout (and where the mouse crosses) stays the same.
$oldLayout = @()
$newLayout = @()
foreach ($display in $before) {
    $oldLayout += [pscustomobject]@{ Device = $display.Device; X = $display.X; Y = $display.Y }
}

$targetState = $before | Where-Object { $_.Device -eq $targetScreen.DeviceName } | Select-Object -First 1
$newLayout += [pscustomobject]@{ Device = $targetScreen.DeviceName; X = 0; Y = 0 }

# Deterministic order: (0,0) is already claimed, so validating the old primary off it is legal.
foreach ($display in $before) {
    if ($display.Device -eq $targetScreen.DeviceName) { continue }
    $newX = if ($display.X -lt 0) { -$display.Width } else { $targetState.Width }
    $newLayout += [pscustomobject]@{ Device = $display.Device; X = $newX; Y = 0 }
}

# Strategy 1: CDS_SET_PRIMARY inside a NORESET batch; Windows moves the rest itself.
$primaryResult = Set-PrimaryDisplay -DeviceName $targetScreen.DeviceName
if (-not $primaryResult.Ok) {
    Write-SetupInfo ("CDS_SET_PRIMARY devolvió $($primaryResult.Code) / commit $($primaryResult.Commit); probando el arreglo completo...")
    $applied = Set-DisplayLayout -Layout $newLayout
    if ($applied.Commit -ne 0 -or $applied.Problems.Count -gt 0) {
        $detail = if ($applied.Problems.Count -gt 0) { " ($($applied.Problems -join ', '))" } else { '' }
        Show-Failure "No se pudo aplicar el cambio: código $($applied.Commit)$detail."
        [void](Set-DisplayLayout -Layout $oldLayout)
        Write-SetupWarning 'Se dejó el arreglo anterior.'
        return
    }
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

# Something went wrong: put the previous arrangement back before returning.
$reason = if ($overlap) { 'quedaron monitores superpuestos' } else { 'Windows no cambió el principal' }
Show-Failure "No se pudo cambiar el principal ($reason).`n`nEn Windows 11 esta build rechaza CDS_NORESET con BADFLAGS, así que ChangeDisplaySettingsEx ya no puede ceder la primacía. Alternativas:`n  - Configuración > Pantalla > elegir monitor > 'Usar como pantalla principal'`n  - MultiMonitorTool (NirSoft, portable): /SetPrimary`n  - Start11 (pago): abre el Start en el monitor del mouse"
[void](Set-DisplayLayout -Layout $oldLayout)
if ($primaryScreen) {
    [void](Set-PrimaryDisplay -DeviceName $primaryScreen.DeviceName)
}
$restored = Get-DisplayState -DeviceNames $deviceNames | Where-Object { $_.X -eq 0 -and $_.Y -eq 0 } | Select-Object -First 1
if ($restored) {
    Write-SetupWarning ("Se restauró {0} como principal." -f $restored.Device)
}
else {
    Write-SetupError 'No se pudo revertir. Abrí Configuración > Pantalla y acomodá a mano.'
}
