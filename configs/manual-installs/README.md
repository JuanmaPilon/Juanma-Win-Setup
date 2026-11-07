# Manual installs (no disponibles en Winget)

Apps instaladas en la PC principal que **no** tienen paquete en Winget y por lo tanto no se restauran solas con el setup.
Esta lista existe para no perderlas en una instalación limpia.

## Cómo usarla

1. Después de correr la etapa de Winget, revisar esta lista.
2. Para cada app, hacer una de estas dos cosas:
   - descargarla desde el link del fabricante, o
   - usar el instalador guardado en `private-configs/manual-installs/<app>/`.
3. Nunca commitear instaladores, claves de licencia ni seriales al repo público.

## Apps

| App                                                    | Por qué es manual                                                                                      | De dónde obtenerla                                                                                                                             |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| ALSEYE BEM (utility del cooler)                        | Sin paquete en Winget                                                                                  | Sitio oficial de ALSEYE (sección de descargas/software, buscar "BEM"). Guardar el instalador en `private-configs/manual-installs/alseye-bem/`. |
| Archon App                                             | Sin paquete en Winget (solo existe un agente de Zorus y un "Archon for ARK" de Store, no relacionados) | Guardar el instalador original en `private-configs/manual-installs/archon/`.                                                                   |
| NVIDIA App + driver                                    | No está en la fuente `winget` (solo existe el ID de Store `XP8CLZL93F5Z4P`)                            | https://www.nvidia.com/en-us/software/nvidia-app/                                                                                              |
| Canon TS3100 (MP Drivers, IJ Scan Utility, Quick Menu) | Suite específica de hardware                                                                           | https://ij.start.canon                                                                                                                         |
| Windhawk (portable)                                    | Sin paquete portable en Winget; se instala con el setup NSIS en modo portable                          | `windhawk_setup.exe /S /PORTABLE /D=<ruta>` (descarga: https://github.com/ramensoftware/windhawk/releases)                                     |

## Notas

- Juegos (Steam, Battle.net, Riot, EA) se reinstalan desde su launcher, no hace falta listarlos.
- Si en el futuro una app manual entra a Winget, moverla a `apps/winget-apps.txt` y borrarla de esta tabla.
