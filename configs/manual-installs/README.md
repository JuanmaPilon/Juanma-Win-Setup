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

`scripts/Install-ManualApps.ps1` lee el manifiesto `configs/manual-installs/apps.json` y hace el paso 2 por vos,
siempre que los archivos estén en `private-configs/manual-installs/<carpeta>/`:

```text
private-configs/manual-installs/          <- git-ignored, nunca se commitea
├── archon\*.exe            NSIS, se ejecuta con /S
├── alseye-bem\*.exe        Inno Setup, se ejecuta con /VERYSILENT
├── nvidia\*.exe            sin switch silencioso: abre la UI
├── canon\*.exe             sin switch silencioso: abre la UI
├── wisp\*.zip              se extrae en %LOCALAPPDATA%\Programs\Wisp
└── multimonitortool\*.zip  se extrae en %LOCALAPPDATA%\Programs\MultiMonitorTool
```

- El glob (`*.exe` / `*.zip`) toma **el archivo más nuevo** de la carpeta: al actualizar no hay que renombrar nada.
- Es **idempotente**: si la app ya está en el registro de desinstalación, o el destino ya tiene ejecutables, la
  saltea. `-Force` reinstala.
- `-DryRun` muestra qué haría sin tocar nada. `-SourceRoot` permite leer de otra carpeta.
- Si falta un archivo, avisa con la ruta exacta y **sigue con el resto**.
- Los zip se extraen **aplanando** la carpeta interna (`wisp-v0.8.0-x86_64-windows/`), así la ruta destino no
  lleva la versión y el autostart no se rompe en cada actualización.

## Apps

| App                                                    | Por qué es manual                                                                                                   | De dónde obtenerla                                                                                                                                                                                                                           |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ALSEYE BEM (utility del cooler)                        | Sin paquete en Winget                                                                                               | [BEM GEN1 (V3.0.0.1)](https://alseyecorp.com/wp-content/uploads/2024/10/ALSEYE-BEM_V3.0.0.1.zip) — está en la sección _SOFTWARE_ del footer de alseyecorp.com, no en la ficha del producto. Inno Setup. **Ojo:** es un downgrade, ver Notas. |
| Archon App                                             | Sin paquete en Winget (solo existe un agente de Zorus y un "Archon for ARK" de Store, no relacionados)              | Guardar el instalador original en `private-configs/manual-installs/archon/`.                                                                                                                                                                 |
| NVIDIA App + driver                                    | No está en la fuente `winget` (solo existe el ID de Store `XP8CLZL93F5Z4P`)                                         | https://www.nvidia.com/en-us/software/nvidia-app/                                                                                                                                                                                            |
| Canon TS3100 (MP Drivers, IJ Scan Utility, Quick Menu) | Suite específica de hardware                                                                                        | https://ij.start.canon                                                                                                                                                                                                                       |
| Wisp (launcher + dock que reemplaza la taskbar)        | Sin paquete en Winget todavía (`SumirSeth.Wisp` no existe en el índice; el repo tiene un `packaging/` preparándolo) | https://github.com/SumirSeth/wisp/releases/latest — extraer el zip en `%LOCALAPPDATA%\Programs\Wisp` y guardar copia en `private-configs/manual-installs/wisp/`. Ver `configs/wisp/README.md`.                                               |
| MultiMonitorTool (NirSoft, cambia el monitor primario) | Sin paquete en Winget                                                                                               | https://www.nirsoft.net/utils/multimonitortool-x64.html — extraer el zip en `%LOCALAPPDATA%\Programs\MultiMonitorTool`. Lo usa `scripts/Toggle-PrimaryDisplay.ps1`; sin él el atajo "Cambiar pantalla principal" no hace nada.               |

## Notas

- **ALSEYE M120DPLUS usa BEM GEN1.** El link directo vive en el footer del sitio (_SOFTWARE → BEM GEN1_), no en
  la página del producto, y esa página tiene un slug de lorem ipsum (`/product/augue-adipiscing-euismod/`) que
  hace parecer que no existe. El zip trae un único `.exe` (instalador Inno Setup, ~13 MB).
- **El GEN1 publicado es 3.0.0.1 y esta PC tiene 3.0.0.3**: el archivo del sitio es un _downgrade_. La etapa lo
  saltea por el `detect` salvo que se pase `-Force`, así que no hay riesgo de bajar de versión sin querer. Si
  aparece una 3.0.0.3 descargable, reemplazá el zip y actualizá esta nota. **"BEM GEN2"** es para productos más
  nuevos, no para el M120DPLUS.
- Juegos (Steam, Battle.net, Riot, EA) se reinstalan desde su launcher, no hace falta listarlos.
- Si en el futuro una app manual entra a Winget, moverla a `apps/winget-apps.txt` y borrarla de esta tabla.
