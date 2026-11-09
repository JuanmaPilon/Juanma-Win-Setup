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
```

Módulos de configuración existentes: `powertoys`, `windows-ui`, `startup`, `terminal`, `windhawk`, `git`, `environment-variables` (script suelto).

## Punto de entrada

- `Menu.cmd` → `scripts/Menu.ps1` (menú interactivo, la vía recomendada).
- `Setup.ps1` → Apps + Import-Configs + Finalize (soporta `-DryRun`, `-SkipApps`, `-SkipConfigs`, `-SkipFinalize`).
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

## Pendientes conocidos

- Export/import de perfil de Firefox (`Export-Firefox.ps1` + `configs/firefox/import.ps1`).
- Startup a nivel máquina (HKLM Run + carpeta Startup común, requiere admin).
- Validación end-to-end en la laptop tras cada cambio grande.
