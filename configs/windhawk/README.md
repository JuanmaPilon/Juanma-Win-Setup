# Windhawk configuration

Restaura la configuración de Windhawk. Soporta los **dos modos** de instalación:

| Modo                                | Almacenamiento                                      | Requiere admin                 |
| ----------------------------------- | --------------------------------------------------- | ------------------------------ |
| **Normal** (servicio) — recomendado | `HKLM\SOFTWARE\Windhawk` + `%ProgramData%\Windhawk` | Sí (import/export de registro) |
| Portable                            | `...\Windhawk\AppData` (INI)                        | No                             |

El export detecta el modo automáticamente (mira `Program Files\Windhawk\windhawk.ini`).

## Instalación del programa

- Normal: `winget install RamenSoftware.Windhawk` → servicio `Windhawk` (arranca con Windows) + tarea `WindhawkRunUITask` (UI al iniciar sesión).
- Portable: `windhawk_setup.exe /S /PORTABLE /D=<ruta>` → sin servicio; el autostart por Run key resultó poco confiable.

## Qué exporta/importa

**Modo normal:**

- `data/windhawk-hklm.reg` (settings de la app, engine y de cada mod)
- `data/windhawk-hkcu.reg` (configs por usuario, si existen)
- `data/ModsSource/*.wh.cpp` (fuentes de los mods instalados)
- `data/Engine/Mods/32|64/*.dll` (**mods ya compilados**: sin estos el motor no puede cargar ningún mod)
- `data/Engine/ModsWritable/mod-storage/*` (estado propio de algunos mods)
- `data/userprofile.json` (lista de mods que muestra la UI)
- `data/mods-manifest.json` (id, versión, arquitectura y binario de cada mod)

**Modo portable:**

- `data/settings.ini`, `data/Engine/settings.ini`
- `data/Engine/Mods/*.ini` (settings por mod), `data/ModsSource/*.wh.cpp`
- `data/UIData/user-data/User/*` (settings de la UI)

Siempre se escribe `data/mode.txt` para que el import sepa qué restaurar. Se excluyen cachés (`Symbols`, `Engine\ModsWritable\mod-status`, WebView/VS Code).

## Flujo en una PC nueva

1. Instalar Windhawk normal (`winget install RamenSoftware.Windhawk`).
2. Abrirlo una vez (crea el servicio y `%ProgramData%\Windhawk`) y **cerrarlo**.
3. Importar el módulo **desde una PowerShell de administrador** (menú → Import config backups, o `configs\windhawk\import.ps1 -RepositoryRoot <repo>`).
4. El import para la UI + el servicio, restaura registro, fuentes, DLLs compilados y `userprofile.json`, y vuelve a arrancar el servicio.
5. Al final imprime una tabla de verificación (`OK`/`FAIL` por mod).

No hace falta reinstalar los mods desde el catálogo: los binarios compilados viajan en el backup.

### Por qué antes no aparecían los mods

El import abortaba en una comprobación de instalación *portable* antes de llegar a la rama de registro, y además solo copiaba `userprofile.json` sin los DLLs referenciados por `HKLM\...\Mods\<id>\LibraryFileName`. Ahora el modo se detecta primero y los binarios se restauran antes de arrancar el servicio.

## Migración portable → normal (completada)

La migración de portable a instalación normal ya se hizo en la PC principal (los settings pasaron de INI a `HKLM`). El soporte portable del export/import queda solo como **fallback de lectura** para backups viejos.

> No mezclar instalaciones: si existe una copia portable vieja abierta, su UI escribe en OTRO storage y los cambios "no se aplican" en el engine del servicio. Usar siempre la UI de `C:\Program Files\Windhawk`.

## Mods usados en la PC principal

- `windows-11-taskbar-styler`
- `windows-11-start-menu-styler`
- `taskbar-notification-icon-spacing`
- `taskbar-tray-system-icon-tweaks`
- `windows-11-notification-center-styler`
- `alt-tab-per-monitor`
- `taskbar-multi-tray`
- `start-menu-open-location`
- `center-new-windows`
- `taskbar-icon-size`

## Advertencias

- No activar "inyectar en juegos" si usás juegos con anti-cheat (Vanguard/LoL).
- Los mods se actualizan desde el catálogo; una update puede cambiar el esquema de settings.
- Los binarios del engine (`Engine\<version>`, `windhawk-mod-shim.dll`, `.whl`) no se respaldan: eso lo reinstala el instalador. Solo viajan los DLLs de los mods.
