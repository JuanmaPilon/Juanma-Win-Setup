# Win-Setup — Instrucciones para agentes

## Propósito del repo

Repositorio personal de infraestructura-como-código para Windows 11 (incluye LTSC IoT).
Objetivo: reinstalar Windows desde cero y dejar la PC **virtualmente idéntica** a la máquina principal (desktop) sin trabajo manual.

Flujo esperado:

1. Instalar Winget.
2. Instalar apps desde la lista de Winget.
3. Importar configuraciones personales exportadas desde el desktop.

Cada máquina puede tener un **nombre de usuario distinto** (`C:\Users\UsuarioA` vs `C:\Users\UsuarioB`), por lo que todo debe ser portable entre perfiles.

## Objetivos clave

- Idempotente: correr dos veces no debe romper nada.
- Modular: un script = una responsabilidad.
- Portable: nunca asumir rutas absolutas de otro perfil ni valores machine-specific.
- Seguro: los backups con datos personales viven en `private-configs/` (ignorado por Git).
- Preferir herramientas oficiales (PowerShell, Winget, APIs soportadas) y evitar hacks de registro salvo que no exista alternativa.

## Arquitectura

```
apps/            winget-apps.txt (lista de paquetes, uno por línea)
configs/<mod>/   import.ps1 + README.md (hooks de restauración, públicos)
scripts/         Export-*.ps1, Install-*.ps1, Import-*.ps1, Menu.ps1
modules/         SetupHelpers.psm1 (helpers compartidos)
registry/        .reg agrupados para cambios excepcionales
private-configs/ backups reales (GIT-IGNORED: nunca commitear)
docs/            notas de decisiones y cosas ya probadas (ej. audio-bluetooth.md)
```

Módulos de configuración existentes: `powertoys`, `windows-ui`, `startup`, `terminal`, `wisp`, `windhawk` (pausado), `git`, `environment-variables` (script suelto).

## Punto de entrada

- `Menu.cmd` → `scripts/Menu.ps1` (menú interactivo, la vía recomendada).
- `Setup.ps1` → Apps + Cleanup + Import-Configs + Finalize (soporta `-DryRun`, `-SkipApps`, `-SkipCleanup`, `-SkipConfigs`, `-SkipFinalize`).
- `scripts/Update-Apps.ps1` → `winget upgrade --all`, reutilizable después de cualquier instalación.
- `scripts/Import-Configs.ps1` ejecuta **todos** los `configs/**/import.ps1` y continúa aunque uno falle.

## Convenciones obligatorias

### PowerShell

- `Set-StrictMode -Version Latest`; exportadores con `$ErrorActionPreference = 'Stop'`, importadores con `'Continue'` (no deben tumbar el setup completo).
- Mensajes de consola **siempre** vía `modules/SetupHelpers.psm1`:
  `Write-SetupStep`, `Write-SetupInfo`, `Write-SetupSuccess`, `Write-SetupWarning`, `Write-SetupError`.
  Los importadores deben importar el módulo con `-Force` (usar helpers sin importarlo rompe el script).
- Resolver rutas del repo desde `$PSScriptRoot`, nunca desde el CWD.
- Parámetros por defecto de salida: `private-configs/<modulo>`.

### Portabilidad

- Nunca hardcodear `C:\Users\<usuario>`. Usar `$env:USERPROFILE`, `%LOCALAPPDATA%`, `%APPDATA%`, `%ProgramData%`.
- Importadores: preferir `private-configs/<mod>` y caer a `configs/<mod>` como fallback público.
- Detectar y omitir valores atados a otro perfil (ej. `C:\Users\Otro\...`) con warning.
- Normalizar rutas del perfil a tokens portables (`%USERPROFILE%`) cuando sea posible.

### Seguridad / privacidad

- `private-configs/` NUNCA se commitea. No escribir nada sensible fuera de ahí.
- Exportadores de env vars: denylist obligatoria (`TEMP`, `TMP`, `USERPROFILE`, `APPDATA`, `LOCALAPPDATA`, etc.).
- Startup: excluir entradas con ejecutables inexistentes (stale) del export.
- Importadores deben ser tolerantes: warning + continuar, nunca abortar el flujo.

### Apps

- `apps/winget-apps.txt`: un package ID de Winget por línea, comentarios con `#`.
- Verificar el ID real con `winget search <nombre>` antes de agregar.
- `apps/winget-remove.txt`: paquetes deprecados que NO deben estar. `scripts/Remove-DeprecatedApps.ps1` los desinstala (stage de `Setup.ps1`, opción 6 del menú, soporta `-DryRun`). Al reemplazar una app, agregar el ID viejo acá.
- Formato de `winget-remove.txt`: `PackageId | DisplayNamePattern | ExtraSilentArgs` (los dos últimos opcionales). El script mata los procesos de la app, intenta `winget uninstall --silent` y cae al uninstaller propio con switch silencioso (`-AllowInteractiveFallback` como último recurso).
- Apps sin paquete en Winget se documentan en `configs/manual-installs/README.md` (solo docs; los instaladores van a `private-configs/manual-installs/`).

### Git

- Repo público = solo código y docs. Backups y exports = `private-configs/`.
- `.gitignore` ya cubre `private-configs/` y bloquea configs públicos sensibles (solo permite `import.ps1` y `README.md`).
- Backup de recuperación: copiar la carpeta `private-configs/` completa a un medio externo (USB, nube o LocalSend a otra PC). Nunca guardarla dentro del repo.

## Patrón para agregar un módulo nuevo (checklist)

1. `scripts/Export-<Modulo>.ps1` → escribe en `private-configs/<modulo>`.
2. `configs/<modulo>/import.ps1` → firma `param([Parameter(Mandatory)][string]$RepositoryRoot)`, soporta `-DryRun` si aplica.
3. `configs/<modulo>/README.md` → qué cubre y cómo se usa.
4. Enganchar el export en `scripts/Menu.ps1` (opción "Export everything").
5. Actualizar `README.md` (cobertura de configs).
6. Validar: errores de sintaxis + async parse (`[System.Management.Automation.Language.Parser]::ParseFile`) + ejecutar export + `import.ps1 -DryRun`.

## Validación antes de terminar cualquier cambio

- Revisar errores del archivo editado (`get_errors`).
- Ejecutar el export real y confirmar que los archivos aparecen en `private-configs/`.
- Ejecutar el import en `-DryRun` y confirmar que no marca como unsafe/inseguro algo legítimo.
- Probar casos borde: rutas con espacios, comandos sin comillas, nombres de usuario distintos.

## Errores ya resueltos (no reintroducir)

- Importar env vars sin filtrar puede romper `TEMP/TMP` en el destino y dejar inutilizables las apps que usan la carpeta temporal (instaladores basados en Squirrel/Electron) → denylist + normalización obligatorias.
- Parser de startup que cortaba comandos sin comillas en el primer espacio → usar regex sobre la ruta con extensión (`.exe|.bat|.cmd|.lnk|.msc|.com`).
- PowerToys: `backup_restore_settings.json` en `%LOCALAPPDATA%/PowerToys` (runtime-backup) y `.ptb` en `Documents/PowerToys/Backup` son necesarios para Command Palette y atajos.
- Visibilidad de íconos de bandeja depende de Windows (`HKCU\Control Panel\NotifyIconSettings`), no de PowerToys.
- Windhawk (modo registro): un mod "existe" solo si están las tres cosas → clave `HKLM\SOFTWARE\Windhawk\Engine\Mods\<id>` (con `LibraryFileName`), el DLL en `%ProgramData%\Windhawk\Engine\Mods\<arch>\<LibraryFileName>` y la entrada en `userprofile.json`. Si falta el DLL, la UI muestra cero mods. El export debe incluir `data/Engine/Mods/32|64/*.dll` (nunca `ModsWritable\mod-status`, es caché) y el import debe **parar la UI** (`Windhawk.exe`) antes de escribir, porque el proceso reescribe `userprofile.json` al cerrarse.
- El import de Windhawk detecta el modo ANTES de cualquier chequeo de ruta portable; antes abortaba con "portable install not found" y nunca tocaba la instalación normal.
- **Nunca** usar un mod de Windhawk con `Include = *`: inyecta el DLL en todos los procesos (juegos con anti-cheat incluidos) y es la causa de crashes. Los mods deben apuntar a procesos del shell (`explorer.exe`, `ShellExperienceHost.exe`, `StartMenuExperienceHost.exe`).
- Wisp (desde 2026-11) reemplaza la taskbar: mantiene su config en `%APPDATA%\wisp\config.toml` (un solo archivo), no necesita admin y se autoregistra en `HKCU\...\Run` como `Wisp`. No tiene paquete en Winget: instalación manual en `%LOCALAPPDATA%\Programs\Wisp`.
- Con `hide_taskbar = true`, los mods de taskbar/tray de Windhawk pierden sentido. Los que siguen aplicando son `windows-11-start-menu-styler`, `windows-11-notification-center-styler` y `notifications-placement` (`monitor = 0` mueve los toasts al monitor del cursor).
- **SoundSwitch descartado (2026-11).** Al cambiar de dispositivo de audio, sobre todo en medio de un juego, provocaba que la PC parpadeara y quedara trabada un momento, como si se reiniciaran todos los dispositivos. No reintroducirlo sin aislar la causa (probable re-enumeración de endpoints). Detalle y alternativas en `docs/audio-bluetooth.md`.
- Audio Bluetooth: los auriculares exponen endpoint `Hands-Free` (manos libres, mono) y A2DP (estéreo). Si Windows agarra el de manos libres, la solución de raíz es destildar "Manos libres Telephony" en Propiedades del dispositivo → pestaña Servicios. No hay herramienta que lo arregle mejor.

## Pendientes conocidos

- Export/import de perfil de Firefox (`Export-Firefox.ps1` + `configs/firefox/import.ps1`).
- Startup a nivel máquina (HKLM Run + carpeta Startup común, requiere admin).
- Audio Bluetooth: confirmar que desactivar "Manos libres Telephony" alcanza (ver `docs/audio-bluetooth.md`) y decidir si hace falta otra herramienta para el dispositivo por defecto, ya que SoundSwitch se descartó.
- Validación end-to-end en la laptop tras cada cambio grande.
