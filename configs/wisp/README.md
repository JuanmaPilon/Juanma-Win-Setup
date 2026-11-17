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

| Ajuste                   | Valor               | Por qué                                                                                                                                                                                                                 |
| ------------------------ | ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `dock_screen`            | `"pointer"`         | El dock aparece en el monitor que tocás con el mouse (y el launcher abre ahí).                                                                                                                                          |
| `hide_taskbar`           | `true`              | Es lo que reemplaza a los mods de taskbar.                                                                                                                                                                              |
| `hotkey`                 | `"Alt+Space"`       | **Conflicto**: es el shortcut por defecto de PowerToys Run. Si activás Run, cambiá uno de los dos.                                                                                                                      |
| `dock_status_group`      | incluye `bluetooth` | Conectar/desconectar los manos libres desde el dock, sin depender del toast de Windows.                                                                                                                                 |
| `file_search_everything` | `true`              | **Necesita Everything instalado y corriendo** (`voidtools.Everything`, ya en `apps/winget-apps.txt`). Sin él, Wisp cae al índice de Windows: más lento y sin cubrir todos los discos. Costo real medido: ~12 MB de RAM. |

Comandos útiles del launcher: `bt` (dispositivos Bluetooth pareados), `wifi off`, `vol 40`, `night light`, `dark mode`, `now` (estado + audio).

## Autostart

Wisp se registra solo con la clave `HKCU\...\Run` llamada `Wisp`. Eso ya lo captura `configs/startup`, así que no hace falta duplicarlo a mano.

## Paneles propios (`surfaces/`)

Wisp permite agregar pantallas propias al launcher: son archivos `.toml` en `%APPDATA%\wisp\surfaces\` y se abren
escribiendo sus `keywords` en el launcher (aparecen como un resultado más; se entra con `Enter`).
No son widgets de escritorio ni botones del dock.

Los bloques disponibles (`kind`) son sólo estos ocho: `clock`, `battery`, `wifi`, `devices`, `volume`,
`outputs`, `apps` (volumen por aplicación) y `media`. No se pueden inventar bloques nuevos.

Este repo respalda `surfaces/*.toml` con `Export-Wisp.ps1`. Panel incluido: `audio.toml` (salidas +
dispositivos Bluetooth + volumen por app + media en una sola pantalla, se abre con `auris` / `sonido`).

> Wisp lee los paneles al arrancar: después de crear o editar uno hay que reiniciarlo para que aparezca.

## Gotchas (cosas que no existen o funcionan distinto)

| Situación                                                   | Solución                                                                                                                                                                                                                                                                         |
| ----------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **No hay botón de Windows/Start en el dock** (solo la lupa) | Es por diseño: las secciones son `launcher`, `apps`, `tray`, `status`, `sound`, `battery`, `wifi`, `bluetooth`, `clock`, y `launcher` es el botón de búsqueda. Para el menú Win+X usá `Win+R` → `devmgmt.msc`, o clic derecho en el chevron `⌄` del dock → **Show the taskbar**. |
| Querés una herramienta de Windows fija en el dock           | Creá un acceso directo al `.msc` en `%APPDATA%\Microsoft\Windows\Start Menu\Programs`; Wisp lo indexa desde `shell:AppsFolder` y se puede pinear (clic derecho → Run as administrator).                                                                                          |
| `Win+X` no aparece                                          | Lo dibuja Explorer anclado a la taskbar, que Wisp oculta. Preferí `Win+R`.                                                                                                                                                                                                       |
| `Alt+Space` no abre Wisp                                    | Choca con PowerToys Run (mismo shortcut por defecto). Cambiá uno de los dos.                                                                                                                                                                                                     |

## Advertencias

- Si Wisp se cierra o crashea, la taskbar de Windows vuelve (con todo el tray). Es la red de seguridad.
- Wisp se actualiza solo (`check_for_updates`); el proyecto es joven y se mueve rápido, así que un cambio de esquema en `config.toml` puede requerir re-exportar.
- Con `hide_taskbar = true`, los mods de taskbar/tray de Windhawk dejan de tener sentido. Los que sí siguen aplicando (`windows-11-start-menu-styler`, `windows-11-notification-center-styler`, `notifications-placement`) no se pisan con Wisp.
