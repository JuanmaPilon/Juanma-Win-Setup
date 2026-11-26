[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    # Donde viven los instaladores. Git-ignored a proposito: nunca viajan con el repo.
    [string]$SourceRoot,
    [switch]$Force,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Import-Module (Join-Path $RepositoryRoot 'modules/SetupHelpers.psm1') -Force

Write-SetupStep 'Apps sin paquete en Winget (instaladores locales)'

if (-not $SourceRoot) {
    $SourceRoot = Join-Path $RepositoryRoot 'private-configs/manual-installs'
}

$manifestPath = Join-Path $RepositoryRoot 'configs/manual-installs/apps.json'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    Write-SetupWarning "No existe el manifiesto ($manifestPath). Se omite la etapa."
    return
}

try {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
}
catch {
    Write-SetupError "El manifiesto no es JSON valido: $($_.Exception.Message)"
    return
}

$apps = @($manifest.apps)
if ($apps.Count -eq 0) {
    Write-SetupWarning 'El manifiesto no tiene ninguna app.'
    return
}

Write-SetupInfo "Instaladores : $SourceRoot"
if (-not (Test-Path -LiteralPath $SourceRoot)) {
    Write-SetupWarning 'La carpeta de instaladores no existe todavia: se van a reportar como faltantes.'
}

# StrictMode: leer una propiedad que no existe en el manifiesto tira error, asi
# que todo acceso pasa por aca.
function Get-AppValue {
    param(
        $App,
        [Parameter(Mandatory = $true)][string]$Name,
        $Default = $null
    )

    if ($null -eq $App) {
        return $Default
    }

    $property = $App.PSObject.Properties[$Name]
    if ($property -and $null -ne $property.Value) {
        return $property.Value
    }
    return $Default
}

function Expand-PathLike {
    param([string]$Value)
    return [System.Environment]::ExpandEnvironmentVariables($Value)
}

# Busca en las tres ramas de desinstalacion y devuelve el DisplayName si esta
# instalado. Sirve para no reinstalar lo que ya esta.
function Get-InstalledDisplayName {
    param([string]$Pattern)

    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    foreach ($root in $roots) {
        foreach ($key in Get-ChildItem $root -ErrorAction SilentlyContinue) {
            $props = Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue
            # Hay claves sin valores: Get-ItemProperty devuelve $null.
            if ($null -eq $props) { continue }
            # StrictMode: las claves sin DisplayName tiran al leer la propiedad.
            $displayName = [string](Get-AppValue $props 'DisplayName' '')
            if ($displayName -and $displayName -like "*$Pattern*") {
                return $displayName
            }
        }
    }

    return $null
}

# Si el zip trae una unica carpeta adentro (wisp-v0.8.0-x86_64-windows/), se sube
# el contenido un nivel. Asi la ruta destino queda estable y no lleva la version
# en el medio (que es lo que rompe el autostart en cada update).
function Expand-ZipFlat {
    param(
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $Destination -Force

    $entries = @(Get-ChildItem -LiteralPath $Destination -Force)
    if ($entries.Count -eq 1 -and $entries[0].PSIsContainer) {
        $inner = $entries[0].FullName
        foreach ($child in @(Get-ChildItem -LiteralPath $inner -Force)) {
            Move-Item -LiteralPath $child.FullName -Destination $Destination -Force
        }
        Remove-Item -LiteralPath $inner -Recurse -Force
    }
}

# Busca el instalador de una app: primero en su carpeta curada y despues plano en
# la raiz de -SourceRoot (bandeja de entrada tipo Downloads\installers, donde los
# archivos caen con nombres libres). Se queda con el mas nuevo por fecha.
function Find-InstallerFile {
    param(
        [Parameter(Mandatory = $true)][string]$Folder,
        [Parameter(Mandatory = $true)][string]$FlatFolder,
        [Parameter(Mandatory = $true)][string[]]$Patterns
    )

    $candidates = @()
    foreach ($patron in $Patterns) {
        if (-not $patron) { continue }
        if (Test-Path -LiteralPath $Folder) {
            $candidates += @(Get-ChildItem -LiteralPath $Folder -Filter $patron -File -ErrorAction SilentlyContinue)
        }
        if (Test-Path -LiteralPath $FlatFolder) {
            $candidates += @(Get-ChildItem -LiteralPath $FlatFolder -Filter $patron -File -ErrorAction SilentlyContinue)
        }
    }

    if ($candidates.Count -eq 0) {
        return $null
    }

    return ($candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
}

$instalados = 0
$omitidos = 0
$faltantes = 0
$fallidos = 0

foreach ($app in $apps) {
    $nombre = [string](Get-AppValue $app 'nombre' (Get-AppValue $app 'id' 'app'))
    $tipo = [string](Get-AppValue $app 'tipo' '')
    $carpetaNombre = [string](Get-AppValue $app 'carpeta' (Get-AppValue $app 'id' 'app'))
    $carpeta = Join-Path $SourceRoot $carpetaNombre

    # Si la app portable ya esta puesta no hace falta el archivo: sin esto, una
    # maquina donde ya esta instalada reportaba "falta el zip" en cada corrida.
    if ($tipo -eq 'zip' -and -not $Force) {
        $destinoPrevio = Expand-PathLike ([string](Get-AppValue $app 'destino' ''))
        if ($destinoPrevio -and (Test-Path -LiteralPath $destinoPrevio) -and
            (@(Get-ChildItem -LiteralPath $destinoPrevio -Filter '*.exe' -File -ErrorAction SilentlyContinue).Count -gt 0)) {
            Write-SetupInfo "$nombre ya esta en $destinoPrevio (usar -Force para reinstalar)."
            $omitidos++
            continue
        }
    }

    $patrones = @(Get-AppValue $app 'patrones' @())
    if ($patrones.Count -eq 0) {
        # Compatibilidad con la version anterior del manifiesto (campo 'archivo').
        $archivoUnico = [string](Get-AppValue $app 'archivo' '')
        if ($archivoUnico) { $patrones = @($archivoUnico) }
    }
    if ($patrones.Count -eq 0) {
        $patrones = @(if ($tipo -eq 'zip') { '*.zip' } else { '*.exe' })
    }

    $archivo = Find-InstallerFile -Folder $carpeta -FlatFolder $SourceRoot -Patterns $patrones

    if (-not $archivo) {
        Write-SetupWarning "Falta el archivo de $nombre (buscaba $($patrones -join ' / ') en $carpeta y en la raiz de la bandeja)."
        $faltantes++
        continue
    }

    if ($tipo -eq 'zip') {
        $destino = Expand-PathLike ([string](Get-AppValue $app 'destino' ''))
        if (-not $destino) {
            Write-SetupWarning "$nombre no tiene 'destino' en el manifiesto; se omite."
            $fallidos++
            continue
        }

        if ($DryRun) {
            Write-SetupInfo "[dry run] extraeria $($archivo.Name) en $destino"
            continue
        }

        Write-SetupProgress -Activity 'Apps manuales' -Status "Extrayendo $nombre"
        try {
            Expand-ZipFlat -ZipPath $archivo.FullName -Destination $destino
            Clear-SetupProgress
            Write-SetupSuccess "$nombre instalado en $destino"
            $instalados++
        }
        catch {
            Clear-SetupProgress
            Write-SetupWarning "No se pudo extraer $nombre : $($_.Exception.Message)"
            $fallidos++
        }
        continue
    }

    # Binario portable de un solo archivo (ej. Wisp): se copia sobre 'destino'.
    if ($tipo -eq 'exe') {
        $destino = Expand-PathLike ([string](Get-AppValue $app 'destino' ''))
        if (-not $destino) {
            Write-SetupWarning "$nombre no tiene 'destino' en el manifiesto; se omite."
            $fallidos++
            continue
        }

        $versionNueva = (Get-Item -LiteralPath $archivo.FullName).VersionInfo.FileVersion

        if ((Test-Path -LiteralPath $destino) -and -not $Force) {
            $versionActual = (Get-Item -LiteralPath $destino).VersionInfo.FileVersion
            if ($versionNueva -and $versionActual -eq $versionNueva) {
                Write-SetupInfo "$nombre ya esta en v$versionActual ($destino)."
                $omitidos++
                continue
            }
        }

        if ($DryRun) {
            Write-SetupInfo "[dry run] copiaria $($archivo.Name) (v$versionNueva) sobre $destino"
            continue
        }

        $destinoDir = Split-Path -Parent $destino
        if (-not (Test-Path -LiteralPath $destinoDir)) {
            New-Item -ItemType Directory -Path $destinoDir -Force | Out-Null
        }

        # Un binario en ejecucion no se puede sobreescribir: reintentar.
        $copiado = $false
        for ($i = 0; $i -lt 12; $i++) {
            try {
                Copy-Item -LiteralPath $archivo.FullName -Destination $destino -Force -ErrorAction Stop
                $copiado = $true
                break
            }
            catch {
                Start-Sleep -Milliseconds 500
            }
        }

        if ($copiado) {
            Write-SetupSuccess "$nombre actualizado a v$versionNueva en $destino (reinicia la app para que tome efecto)."
            $instalados++
        }
        else {
            Write-SetupWarning "No se pudo copiar $nombre : el binario esta en ejecucion. Cerralo y volve a correr la etapa."
            $fallidos++
        }
        continue
    }

    if ($tipo -eq 'installer') {
        $detect = [string](Get-AppValue $app 'detect' '')
        if ($detect) {
            $existente = Get-InstalledDisplayName -Pattern $detect
            if ($existente -and -not $Force) {
                Write-SetupInfo "$nombre ya esta instalado ($existente)."
                $omitidos++
                continue
            }
        }

        $argList = @()
        $silentArgs = [string](Get-AppValue $app 'silentArgs' '')
        if ($silentArgs.Trim()) {
            $argList = @($silentArgs.Trim() -split '\s+')
        }

        if ($DryRun) {
            if ($argList.Count -gt 0) {
                Write-SetupInfo "[dry run] ejecutaria $($archivo.Name) $($argList -join ' ')"
            }
            else {
                Write-SetupInfo "[dry run] ejecutaria $($archivo.Name) SIN switch silencioso (va a pedir UI)"
            }
            continue
        }

        if ($argList.Count -eq 0) {
            Write-SetupWarning "$nombre no tiene silentArgs: se abre el instalador y hay que seguir a mano."
        }

        Write-SetupProgress -Activity 'Apps manuales' -Status "Instalando $nombre"
        $proc = if ($argList.Count -gt 0) {
            Start-Process -FilePath $archivo.FullName -ArgumentList $argList -Wait -PassThru
        }
        else {
            Start-Process -FilePath $archivo.FullName -Wait -PassThru
        }
        Clear-SetupProgress

        # 3010 = instalado, pide reinicio.
        if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
            Write-SetupSuccess "$nombre instalado (exit $($proc.ExitCode))."
            $instalados++
        }
        else {
            Write-SetupWarning "$nombre devolvio exit $($proc.ExitCode)."
            $fallidos++
        }
        continue
    }

    Write-SetupWarning "Tipo desconocido '$tipo' para $nombre; se omite."
    $fallidos++
}

Write-SetupRule
Write-SetupInfo "Instalados: $instalados | Omitidos: $omitidos | Faltantes: $faltantes | Fallidos: $fallidos"

if ($DryRun) {
    Write-SetupSuccess 'Dry run completado (no se instalo nada).'
}
elseif ($faltantes -gt 0 -or $fallidos -gt 0) {
    Write-SetupWarning 'Quedaron apps pendientes; el resto del setup sigue igual.'
}
else {
    Write-SetupSuccess 'Apps manuales listas.'
}
