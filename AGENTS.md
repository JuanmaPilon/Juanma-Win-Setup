# AGENTS.md

Guía para cualquier agente (Copilot, Claude Code, Codex, Cursor, etc.) que trabaje en este repo.
Este archivo es la **fuente de verdad**. `.github/copilot-instructions.md` sólo apunta acá.

---

## Qué es este repo

Infraestructura-como-código para **Windows 11** (incluye LTSC IoT). El objetivo es reinstalar Windows
desde cero y dejar la PC **virtualmente idéntica** a una máquina de referencia, sin trabajo manual.
Es un repo **público**: sólo código, scripts y documentación.

Flujo esperado en una máquina nueva:

1. Instalar Winget.
2. Instalar apps desde `apps/winget-apps.txt` y desinstalar lo deprecado de `apps/winget-remove.txt`.
3. Importar los backups de configuración desde `private-configs/` (copiados a mano desde la máquina de referencia).

## Reglas que no se negocian

1. **`private-configs/` nunca se commitea.** Contiene datos personales. Está en `.gitignore` y ahí se queda.
2. **Nunca hardcodear `C:\Users\<usuario>`.** Usar `$env:USERPROFILE`, `%APPDATA%`, `%LOCALAPPDATA%`,
   `%ProgramData%`. Cada máquina puede tener un nombre de usuario distinto y todo tiene que seguir funcionando.
3. **Idempotente.** Correr cualquier script dos veces no debe romper nada ni duplicar estado.
4. **Un script = una responsabilidad.** No mezclar etapas.
5. **Nunca commitear** instaladores, claves de licencia, seriales, tokens ni capturas con datos personales.
6. **No inventar rutas ni IDs de paquetes.** Verificar con `winget search <nombre>` antes de agregar un ID.
7. **No usar hacks de registro** si existe una API soportada o un setting documentado.

## Convenciones de PowerShell

- `Set-StrictMode -Version Latest` en todos los scripts.
- Exportadores: `$ErrorActionPreference = 'Stop'` (si falla el export, tiene que fallar fuerte).
- Importadores: `$ErrorActionPreference = 'Continue'` (warning + seguir, nunca abortar el setup completo).
- **Todo mensaje de consola va por `modules/SetupHelpers.psm1`**: `Write-SetupStep`, `Write-SetupInfo`,
  `Write-SetupSuccess`, `Write-SetupWarning`, `Write-SetupError`, `Write-SetupBanner`, `Write-SetupRule`,
  `Write-SetupMenuItem`, `Write-SetupProgress`, `Clear-SetupProgress`.
  Los importadores **deben** importar el módulo con `-Force` o los helpers no existen.
- Resolver rutas desde `$PSScriptRoot`, nunca desde el directorio actual.
- Todo importador acepta `-RepositoryRoot` y `-DryRun`, y hace backup de lo que pisa (`*.bak-<timestamp>`).

## Flujo de trabajo con Git

Este es un **repo personal**: el dueño maneja las ramas y trabaja directo sobre `main`.

- **Commitear y pushear directo a `main`.** No crear ramas de feature, no abrir PRs, no hacer forks.
  Las "buenas prácticas" de PR + review no aplican acá; no las propongas.
- Los avisos del remoto al pushear (`Bypassed rule violations for refs/heads/main`: *Commits must have
  verified signatures*, *Changes must be made through a pull request*, *Cannot change this locked branch*)
  son **esperados**: hay branch protection configurada en GitHub y el push pasa por ser el dueño.
  No hay nada que arreglar — **no** cambies la configuración del repo ni abras un PR para "cumplir".
- Mensajes de commit en imperativo y con scope, como los que ya usa el repo:
  `feat(wisp):`, `fix(windhawk):`, `docs(audio):`, `chore:`. Un commit por cambio coherente.
  Si el "por qué" no es obvio, agregar un segundo `-m` con el cuerpo.
- Nunca `git push --force` ni reescribir historia ya pusheada, salvo pedido explícito del dueño.
- Validar antes de commitear: ver la receta de validación más abajo.

## Mapa del repo

| Ruta                        | Qué hay                                                                                     |
| --------------------------- | ------------------------------------------------------------------------------------------- |
| `Menu.cmd`                  | Launcher recomendado → `scripts/Menu.ps1`                                                   |
| `Setup.ps1`                 | Pipeline completo: Apps → Cleanup → Import-Configs → Finalize                               |
| `apps/winget-apps.txt`      | IDs de Winget a instalar, uno por línea, `#` para comentarios                               |
| `apps/winget-remove.txt`    | Denylist de paquetes deprecados: `PackageId \| DisplayNamePattern \| ExtraSilentArgs`       |
| `configs/<mod>/`            | `import.ps1` + `README.md` de cada módulo (público: sólo esos dos archivos)                 |
| `scripts/`                  | `Export-*.ps1`, `Install-*.ps1`, `Import-*.ps1`, `Remove-*.ps1`, `Update-*.ps1`, `Menu.ps1` |
| `modules/SetupHelpers.psm1` | Helpers compartidos de consola y Winget                                                     |
| `registry/`                 | `.reg` agrupados para cambios excepcionales (vacío por ahora)                               |
| `docs/`                     | Notas de decisiones y cosas ya probadas                                                     |
| `private-configs/`          | Backups reales. **GIT-IGNORED**                                                             |

Módulos de configuración: `powertoys`, `windows-ui`, `startup`, `terminal`, `wisp`, `windhawk` (pausado),
`git`, `manual-installs` (sólo docs).

El backup de recuperación es **copiar la carpeta `private-configs/` completa** a un medio externo (USB,
nube, otra PC). No existe script de empaquetado a propósito: nunca dejarla dentro del repo.

El cleanup de apps deprecadas mata los procesos de la app, prueba `winget uninstall --silent` y cae al
uninstaller propio con su switch silencioso (MSI `/qn`, NSIS `/S`, Inno `/VERYSILENT`, Squirrel, familia
Firefox `helper.exe -ms`). `-AllowInteractiveFallback` es el último recurso, opt-in.

## Puntos de entrada y comandos

```powershell
# menú interactivo (vía recomendada, incluye detección de admin y elevación)
.\Menu.cmd

# pipeline completo; soporta -DryRun, -SkipApps, -SkipCleanup, -SkipConfigs, -SkipFinalize
.\Setup.ps1 -DryRun
```

Etapas sueltas:

| Etapa                  | Script                                                                                   | `-DryRun`       |
| ---------------------- | ---------------------------------------------------------------------------------------- | --------------- |
| Instalar Winget        | `scripts/Install-Winget.ps1`                                                             | —               |
| Instalar apps          | `scripts/Install-Apps.ps1 -RepositoryRoot .`                                             | sí              |
| Desinstalar deprecados | `scripts/Remove-DeprecatedApps.ps1 -RepositoryRoot .`                                    | sí              |
| Importar configs       | `scripts/Import-Configs.ps1 -RepositoryRoot .` (propaga `-DryRun` a todos los importers) | sí              |
| Actualizar todo        | `scripts/Update-Apps.ps1 -RepositoryRoot .`                                              | sí (sólo lista) |
| Exportar todo          | opción 5 del menú, o `scripts/Export-<Modulo>.ps1`                                       | —               |
| Finalize               | `scripts/Finalize.ps1 -RepositoryRoot .`                                                 | —               |

### Cambiar el monitor principal (modo trabajo / juego)

`Toggle-Display.cmd` → `scripts/Toggle-PrimaryDisplay.ps1`. Pone el monitor que **no** es principal en
`(0,0)` con `ChangeDisplaySettingsEx` + `CDS_SET_PRIMARY`, que es la única forma de cambiarlo por código
(no hay API pública). Sirve para tener el Start, los toasts y los flyouts en el monitor que estás mirando
sin dejar de usar el otro para juegos.

- `-DryRun` muestra el layout y qué haría, sin tocar nada.
- Verifica el resultado leyendo la posición de cada monitor desde el driver y **revierte solo** si queda mal
  o si detecta monitores superpuestos.
- Windows **siempre** abre el Start y los toasts en el principal; no hay setting que lo cambie. Esto es lo
  único que lo resuelve sin pagar Start11.

El atajo vive en `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Cambiar pantalla principal.lnk` porque Wisp
sólo puede pinear apps de `shell:AppsFolder`. Ese `.lnk` tiene la ruta absoluta del repo, así que en otra
máquina hay que recrearlo:

```powershell
$ws = New-Object -ComObject WScript.Shell
$sc = $ws.CreateShortcut("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Cambiar pantalla principal.lnk")
$sc.TargetPath = (Join-Path (Get-Location) 'Toggle-Display.cmd')
$sc.WorkingDirectory = (Get-Location).Path
$sc.WindowStyle = 7
$sc.Save()
```

## Cómo validar un cambio (obligatorio antes de dar por terminado)

```powershell
# 1. Sintaxis (no ejecuta nada)
foreach ($f in @('.\Setup.ps1', '.\scripts\Menu.ps1', '.\configs\wisp\import.ps1')) {
    $e = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $f), [ref]$null, [ref]$e)
    if ($e.Count) { $e | ForEach-Object { "$f L$($_.Extent.StartLineNumber): $($_.Message)" } } else { "OK $f" }
}

# 2. Importers en seco
.\configs\wisp\import.ps1 -RepositoryRoot . -DryRun

# 3. Pipeline en seco (no instala ni escribe nada)
.\Setup.ps1 -DryRun -SkipApps -SkipCleanup -SkipFinalize
```

Además: si tocaste un exportador, **corrélo de verdad** y confirmá que los archivos aparecen en
`private-configs/<mod>`. Si tocaste un importador, probá un caso borde (ruta con espacios, comando sin
comillas, usuario distinto).

## Cómo agregar un módulo de configuración

1. `scripts/Export-<Modulo>.ps1` → escribe en `private-configs/<modulo>` (default), regenerando el árbol limpio.
2. `configs/<modulo>/import.ps1` → `param([Parameter(Mandatory)][string]$RepositoryRoot, [switch]$DryRun)`,
   prefiere `private-configs/` y cae a `configs/` como fallback público.
3. `configs/<modulo>/README.md` → qué cubre, cómo se usa, gotchas.
4. Enganchar el export en la opción "Export everything" de `scripts/Menu.ps1`.
5. Agregar la protección en `.gitignore` (ignorar todo el módulo y permitir sólo `import.ps1` y `README.md`).
6. Actualizar `README.md` y este archivo.
7. Validar con la receta de arriba.

## Permisos de administrador

Necesitan elevación: el import de Windhawk (escribe `HKLM` + `%ProgramData%` + servicio) y cualquier cosa
de nivel máquina. El menú detecta si la sesión es admin y ofrece relanzarse elevado. Si un script descubre
que le falta elevación, tiene que **decirlo fuerte y salir limpio** (no fallar a medias).

## Trampas ya resueltas (no reintroducir)

- **Variables de entorno sin filtrar** rompen `TEMP`/`TMP` en el destino y dejan inutilizables los instaladores
  basados en Squirrel/Electron. Denylist obligatoria (`TEMP`, `TMP`, `USERPROFILE`, `APPDATA`, `LOCALAPPDATA`, …)
  y normalización de rutas del perfil a tokens portables.
- **Parser de startup**: cortar el comando en el primer espacio rompe rutas sin comillas con espacios.
  Usar regex sobre la ruta con extensión (`.exe|.bat|.cmd|.lnk|.msc|.com`). Además, filtrar entradas _stale_
  (ejecutable inexistente) al exportar: si en el backup ves una entrada muerta, volvé a correr el export.
- **Windhawk (modo registro)**: un mod "existe" sólo si están las tres cosas → clave
  `HKLM\SOFTWARE\Windhawk\Engine\Mods\<id>` con `LibraryFileName`, el DLL en
  `%ProgramData%\Windhawk\Engine\Mods\<arch>\<LibraryFileName>`, y la entrada en `userprofile.json`.
  Si falta el DLL, la UI muestra cero mods. El export debe incluir los DLLs; el import debe **parar la UI**
  (`Windhawk.exe`) antes de escribir, porque el proceso reescribe `userprofile.json` al cerrarse.
- **El import de Windhawk detecta el modo ANTES** de cualquier chequeo de ruta portable; antes abortaba con
  "portable install not found" y nunca tocaba la instalación normal.
- **Nunca** un mod de Windhawk con `Include = *`: inyecta el DLL en todos los procesos, juegos con anti-cheat
  incluidos, y es la causa de crashes. Los mods deben apuntar a procesos del shell
  (`explorer.exe`, `ShellExperienceHost.exe`, `StartMenuExperienceHost.exe`).
- **Importadores que no frenan la app dueña del archivo** escriben y después la app pisa todo al cerrarse.
  Patrón: parar → escribir → volver a arrancar (Windhawk, Wisp).
- **PowerToys**: `backup_restore_settings.json` en `%LOCALAPPDATA%\PowerToys` y el `.ptb` en
  `Documents/PowerToys/Backup` son necesarios para Command Palette y atajos. La visibilidad de íconos de
  bandeja depende de Windows (`HKCU\Control Panel\NotifyIconSettings`), no de PowerToys.
- **`-DryRun` tiene que propagarse** de punta a punta. Un `Setup.ps1 -DryRun` que escribe de verdad es un bug.
- **Apps instaladas fuera de Winget** no aparecen en `winget list`: el cleanup no las ve. Si una app se
  instaló a mano, hay que sacarla a mano o documentarla en `configs/manual-installs/README.md`.

## Estado actual de las decisiones (2026-11)

- **Wisp reemplazó a Windhawk** para la taskbar: es un dock + launcher (Rust, ~2 MB, sin admin) que oculta
  la taskbar de Windows. Config en `%APPDATA%\wisp\config.toml` (un solo archivo), autostart vía
  `HKCU\...\Run` como `Wisp`. **No tiene paquete en Winget**: instalación manual en
  `%LOCALAPPDATA%\Programs\Wisp`. No tiene botón de Start en el dock (sólo el de búsqueda).
- **Windhawk quedó pausado**, no borrado: sigue en `apps/winget-remove.txt` y su backup sirve de rollback.
  Con `hide_taskbar = true` los mods de taskbar/tray pierden sentido; los que siguen aplicando son
  `windows-11-start-menu-styler`, `windows-11-notification-center-styler` y `notifications-placement`.
- **FancyZones** cubre "abrir ventanas nuevas en el monitor activo" (`openWindowOnActiveMonitor = true`).
  No hace falta un mod para eso, y tener los dos compitiendo rompe el resultado.
- **SoundSwitch en reevaluación (2026-11).** El primer intento se descartó porque al cambiar de dispositivo,
  sobre todo en juego, la PC parpadeaba y quedaba trabada. El registro de eventos no muestra ni un `TDR`
  (4101) ni reinicios de `Audiosrv`, así que la causa es el **banner overlay**, no el audio. Se está
  reintentando con notificaciones en `Sound only` y sin triggers. Protocolo y criterio de corte en
  `docs/audio-bluetooth.md`. Si vuelve a fallar, `FortyOneLtd.AudioSwitcher` es el plan B.
- **Audio Bluetooth**: los auriculares exponen `Hands-Free` (mono, calidad de llamada) y A2DP (estéreo).
  La solución de raíz es destildar "Manos libres Telephony" en las propiedades del dispositivo.

## Pendientes conocidos

- Export/import del perfil de Firefox (`Export-Firefox.ps1` + `configs/firefox/import.ps1`).
- Startup a nivel máquina (`HKLM\...\Run` + carpeta Startup común), requiere admin.
- Validar si el toggle de "Manos libres Telephony" alcanza como solución completa de audio.
- `configs/git/README.md` falta (existe el `import.ps1`).
- Validación end-to-end en una segunda máquina después de cada cambio grande.
- **Bootstrap de repos propios (idea, a definir).** El setup debería clonar 2 repos personales en una carpeta
  de trabajo para tenerlos listos desde el primer arranque. Falta definir: cuáles repos, en qué ruta destino,
  y cómo resolver credenciales (los repos privados necesitan auth; no guardar tokens en el repo). Requisitos
  ya claros: idempotente (`git clone` si no existe, `git pull` si existe), tolerante a fallos de red, y
  `-DryRun` soportado. Nunca hardcodear la ruta del usuario.

## Dónde está el detalle

- `README.md` — visión general y quick start.
- `docs/README.md` — índice de notas de decisiones.
- `docs/audio-bluetooth.md` — audio/Bluetooth: qué se probó y por qué.
- `configs/<mod>/README.md` — cada módulo, con sus gotchas.
- `configs/manual-installs/README.md` — apps sin paquete en Winget.
