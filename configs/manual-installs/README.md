# Manual installs (no disponibles en Winget)

Apps instaladas en la PC principal que **no** tienen paquete en Winget y por lo tanto no se restauran solas con el setup.
Esta lista existe para no perderlas en una instalación limpia.

## Cómo usarla

1. Después de correr la etapa de Winget, revisar esta lista.
2. Para cada app, hacer una de estas dos cosas:
   - descargarla desde el link del fabricante, o
   - usar el instalador guardado en `private-configs/manual-installs/<app>/`.
3. Nunca commitear instaladores, claves de licencia ni seriales al repo público.

## Instalación automática (opcional)

`scripts/Install-ManualApps.ps1` lee el manifiesto `configs/manual-installs/apps.json` y hace el paso 2 por vos.

### De dónde lee los instaladores

Hay dos orígenes, y el script mira los dos en este orden:

1. **Carpeta curada:** `private-configs/manual-installs/<carpeta>/` (git-ignored). Es la copia buena, la que viaja
   en el backup.
2. **Bandeja plana:** la raíz del `-SourceRoot`. Sirve para dejar los instaladores recién bajados **sin ordenar**, con
   el nombre que trae el fabricante (`Wisp.exe`, `Cannon Pixma TS1130.exe`, `ALSAYE M120D PLUS.exe`).

```powershell
# bandeja de entrada: descargas sueltas, sin subcarpetas
.\scripts\Install-ManualApps.ps1 -RepositoryRoot . -SourceRoot "$env:USERPROFILE\Downloads"
```

Cada app declara una lista `patrones` de globs. Se prueban todos contra la carpeta curada y contra la raíz, y
**gana el archivo más nuevo por fecha**. Por eso actualizar es sólo dejar el `.exe` nuevo en la bandeja: no hay que
renombrar nada ni borrar el viejo.

### Tipos

```text
private-configs/manual-installs/          <- git-ignored, nunca se commitea
├── archon\*.exe            installer NSIS, /S
├── alseye-bem\*.exe        installer Inno Setup, /VERYSILENT
├── nvidia\*.exe            installer sin switch silencioso: abre la UI
├── canon\*.exe             installer sin switch silencioso: abre la UI
├── wisp\*.exe              exe portable: se copia sobre %LOCALAPPDATA%\Programs\Wisp\wisp.exe
└── multimonitortool\*.zip  zip: se extrae en %LOCALAPPDATA%\Programs\MultiMonitorTool
```

| `tipo`      | Qué hace                                                                                     |
| ----------- | -------------------------------------------------------------------------------------------- |
| `installer` | Ejecuta el archivo con `silentArgs`. Si está vacío, abre la UI. Acepta exit `0` y `3010`.      |
| `zip`       | Extrae en `destino`, aplanando la carpeta interna si el zip trae una sola.                    |
| `exe`       | Copia el binario portable sobre `destino` (ruta completa del `.exe`). No reinicia la app.     |

- Es **idempotente**: si la app ya está en el registro de desinstalación (para `installer`), o el destino ya tiene
  ejecutables (para `zip`), o el `destino` ya tiene la misma versión (para `exe`), la saltea. `-Force` reinstala.
- `-DryRun` muestra qué haría sin tocar nada.
- Si falta un archivo, avisa con la ruta exacta y **sigue con el resto**.
- Los zip se extraen **aplanando** la carpeta interna (`wisp-v0.8.0-x86_64-windows/`), así la ruta destino no
  lleva la versión y el autostart no se rompe en cada actualización.
- El tipo `exe` **no** mata ni reinicia el proceso: si la app estaba abierta, la copia falla y avisa. Cerrá la app y
  volvé a correr la etapa. El reintento con espera cubre el caso de un proceso que todavía está terminando.

## Apps

| App                                                    | Por qué es manual                                                                                                   | De dónde obtenerla                                                                                                                                                                                                                     |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ALSEYE BEM (utility del cooler)                        | Sin paquete en Winget                                                                                               | [BEM GEN1](https://alseyecorp.com/wp-content/uploads/2024/10/ALSEYE-BEM_V3.0.0.1.zip) — está en la sección _SOFTWARE_ del footer de alseyecorp.com, no en la ficha del producto. Inno Setup. Ver Notas.                                |
| Archon App                                             | Sin paquete en Winget (solo existe un agente de Zorus y un "Archon for ARK" de Store, no relacionados)              | Guardar el instalador original en `private-configs/manual-installs/archon/`.                                                                                                                                                           |
| NVIDIA App + driver                                    | No está en la fuente `winget` (solo existe el ID de Store `XP8CLZL93F5Z4P`)                                         | https://www.nvidia.com/en-us/software/nvidia-app/                                                                                                                                                                                      |
| Canon TS3100 (MP Drivers, IJ Scan Utility, Quick Menu) | Suite específica de hardware                                                                                        | https://ij.start.canon — el archivo del fabricante se llama "TS1130", pero el paquete que instala es "TS3100 series".                                                                                                                 |
| Wisp (launcher + dock que reemplaza la taskbar)        | Sin paquete en Winget todavía (`SumirSeth.Wisp` no existe en el índice; el repo tiene un `packaging/` preparándolo) | https://github.com/SumirSeth/wisp/releases/latest — desde la 0.9.0 el release trae un **`.exe` portable único** (antes era un zip). Ver `configs/wisp/README.md`.                                                                     |
| MultiMonitorTool (NirSoft, cambia el monitor primario) | Sin paquete en Winget                                                                                               | https://www.nirsoft.net/utils/multimonitortool-x64.html — extraer el zip en `%LOCALAPPDATA%\Programs\MultiMonitorTool`. Lo usa `scripts/Toggle-PrimaryDisplay.ps1`; sin él el atajo "Cambiar pantalla principal" no hace nada. |

## Notas

- **ALSEYE M120DPLUS usa BEM GEN1.** El link directo vive en el footer del sitio (_SOFTWARE → BEM GEN1_), no en
  la página del producto, y esa página tiene un slug de lorem ipsum (`/product/augue-adipiscing-euismod/`) que
  hace parecer que no existe. El zip trae un único `.exe` (instalador Inno Setup, ~13 MB).
- **La versión descargable del sitio (3.0.0.1) era un _downgrade_ y ya no se usa**: esta PC corre 3.0.0.3, y el
  instalador `ALSAYE M120D PLUS.exe` que publica el mismo footer **es 3.0.0.3** (mismo `ProductName` = `ALSEYE BEM`).
  Ese es el que queda en `private-configs/manual-installs/alseye-bem/`; el 3.0.0.1 se borró. **"BEM GEN2"** es
  para productos más nuevos, no para el M120DPLUS.
- **Wisp cambió de formato en 0.9.0**: pasó de zip a un `.exe` portable de un solo archivo (~2,5 MB). Por eso el
  manifiesto ahora lo declara como `tipo: "exe"` con `destino` = ruta completa del binario. El zip 0.8.0 quedó
  guardado en `private-configs/manual-installs/wisp/` sólo como rollback manual.
- Juegos (Steam, Battle.net, Riot, EA) se reinstalan desde su launcher, no hace falta listarlos.
- Si en el futuro una app manual entra a Winget, moverla a `apps/winget-apps.txt` y borrarla de esta tabla.
