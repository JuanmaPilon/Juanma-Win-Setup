# Wisp configuration

[Wisp](https://github.com/SumirSeth/wisp) es un launcher + dock para Windows 11 que **reemplaza la taskbar**: la oculta y dibuja su propio dock (apps, tray, estado, reloj) que sigue al monitor donde está el mouse. Reemplaza en este repo a los mods de taskbar de Windhawk.

## Instalación del programa

No hay paquete en Winget todavía (`SumirSeth.Wisp` no existe en el índice). Instalación manual:

1. Descargar `wisp-vX-x86_64-windows.zip` del [último release](https://github.com/SumirSeth/wisp/releases/latest).
2. Extraer en `%LOCALAPPDATA%\Programs\Wisp`.
3. Ejecutar `wisp.exe` (abre Settings y registra el autostart + el shortcut).

> **Nunca** dejar Wisp corriendo desde `Downloads`: el backup de startup guarda la ruta del `.exe`, y en otra PC esa ruta no existe.

Wisp no está firmado, así que SmartScreen va a avisar la primera vez (Más información → Ejecutar de todas formas).

## Qué exporta/importa

- `config.toml` — toda la configuración (dock, launcher, apariencia, búsqueda).
- `surfaces/*.toml` — paneles propios del launcher, si los tenés.
- `_install.txt` — versión y ruta del `.exe` desde donde se exportó (solo diagnóstico).

Se exporta a `private-configs/wisp/` y se restaura a `%APPDATA%\wisp\`.

## Flujo en una PC nueva

1. Instalar Wisp en `%LOCALAPPDATA%\Programs\Wisp` y abrirlo una vez (crea `%APPDATA%\wisp\config.toml`).
2. Menú → **Import config backups** (o `configs\wisp\import.ps1 -RepositoryRoot <repo>`).
3. El import para Wisp, escribe `config.toml`, y lo vuelve a arrancar.

No necesita admin.

## Ajustes que importan en este setup

| Ajuste | Valor | Por qué |
| ------ | ----- | ------- |
| `dock_screen` | `"pointer"` | El dock aparece en el monitor que tocás con el mouse (y el launcher abre ahí). |
| `hide_taskbar` | `true` | Es lo que reemplaza a los mods de taskbar. |
| `hotkey` | `"Alt+Space"` | **Conflicto**: es el shortcut por defecto de PowerToys Run. Si activás Run, cambiá uno de los dos. |
| `dock_status_group` | incluye `bluetooth` | Conectar/desconectar los manos libres desde el dock, sin depender del toast de Windows. |

Comandos útiles del launcher: `bt` (dispositivos Bluetooth pareados), `wifi off`, `vol 40`, `night light`, `dark mode`, `now` (estado + audio).

## Autostart

Wisp se registra solo con la clave `HKCU\...\Run` llamada `Wisp`. Eso ya lo captura `configs/startup`, así que no hace falta duplicarlo a mano.

## Advertencias

- Si Wisp se cierra o crashea, la taskbar de Windows vuelve (con todo el tray). Es la red de seguridad.
- Wisp se actualiza solo (`check_for_updates`); el proyecto es joven y se mueve rápido, así que un cambio de esquema en `config.toml` puede requerir re-exportar.
- Con `hide_taskbar = true`, los mods de taskbar/tray de Windhawk dejan de tener sentido. Los que sí siguen aplicando (`windows-11-start-menu-styler`, `windows-11-notification-center-styler`, `notifications-placement`) no se pisan con Wisp.
