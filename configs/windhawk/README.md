# Windhawk configuration

Restaura la configuración de Windhawk. Soporta los **dos modos** de instalación:

| Modo | Almacenamiento | Requiere admin |
|---|---|---|
| **Normal** (servicio) — recomendado | `HKLM\SOFTWARE\Windhawk` + `%ProgramData%\Windhawk` | Sí (import/export de registro) |
| Portable | `...\Windhawk\AppData` (INI) | No |

El export detecta el modo automáticamente (mira `Program Files\Windhawk\windhawk.ini`).

## Instalación del programa

- Normal: `winget install RamenSoftware.Windhawk` → servicio `Windhawk` (arranca con Windows) + tarea `WindhawkRunUITask` (UI al iniciar sesión).
- Portable: `windhawk_setup.exe /S /PORTABLE /D=<ruta>` → sin servicio; el autostart por Run key resultó poco confiable.

## Qué exporta/importa

**Modo normal:**
- `data/windhawk-hklm.reg` (settings de la app, engine y de cada mod)
- `data/windhawk-hkcu.reg` (configs por usuario, si existen)
- `data/ModsSource/*.wh.cpp` (fuentes de los mods instalados)
- `data/userprofile.json`

**Modo portable:**
- `data/settings.ini`, `data/Engine/settings.ini`
- `data/Engine/Mods/*.ini` (settings por mod), `data/ModsSource/*.wh.cpp`
- `data/UIData/user-data/User/*` (settings de la UI)

Siempre se escribe `data/mode.txt` para que el import sepa qué restaurar. Se excluyen cachés (`Symbols`, WebView/VS Code).

## Flujo en una PC nueva

1. Instalar Windhawk normal (`winget install RamenSoftware.Windhawk`).
2. Abrirlo una vez y **reinstalar los mods desde el catálogo** (los DLLs compilados no viajan; las fuentes sí).
3. Importar el módulo **desde una PowerShell de administrador** (menú → Import config backups, o `configs\windhawk\import.ps1 -RepositoryRoot <repo>`).
4. El servicio Windhawk se reinicia solo al final.

## Migración portable → normal (una sola vez)

`scripts\Migrate-WindhawkPortableToRegistry.ps1` lee los `.ini` del backup portable y escribe los settings al registro (HKLM). Correr **como administrador**, con los mods ya instalados:

```powershell
.\scripts\Migrate-WindhawkPortableToRegistry.ps1 -RepositoryRoot . -DryRun   # previsualizar
.\scripts\Migrate-WindhawkPortableToRegistry.ps1 -RepositoryRoot .
```

## Mods usados en la PC principal

- `windows-11-taskbar-styler`
- `windows-11-start-menu-styler`
- `taskbar-notification-icon-spacing`
- `taskbar-tray-system-icon-tweaks`

## Advertencias

- No activar "inyectar en juegos" si usás juegos con anti-cheat (Vanguard/LoL).
- Los mods se actualizan desde el catálogo; una update puede cambiar el esquema de settings.
- Los binarios del engine no se respaldan (se reinstalan con el instalador); solo viaja la configuración.

