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
- Los avisos del remoto al pushear (`Bypassed rule violations for refs/heads/main`: _Commits must have
  verified signatures_, _Changes must be made through a pull request_, _Cannot change this locked branch_)
  son **esperados**: hay branch protection configurada en GitHub y el push pasa por ser el dueño.
  No hay nada que arreglar — **no** cambies la configuración del repo ni abras un PR para "cumplir".
- Mensajes de commit en imperativo y con scope, como los que ya usa el repo:
  `feat(wisp):`, `fix(repos):`, `docs(audio):`, `chore:`. Un commit por cambio coherente.
  Si el "por qué" no es obvio, agregar un segundo `-m` con el cuerpo.
- Nunca `git push --force` ni reescribir historia ya pusheada, salvo pedido explícito del dueño.
- Validar antes de commitear: ver la receta de validación más abajo.

## Mapa del repo

| Ruta                        | Qué hay                                                                                     |
| --------------------------- | ------------------------------------------------------------------------------------------- |
| `Menu.cmd`                  | Launcher recomendado → `scripts/Menu.ps1`                                                   |
| `Setup.ps1`                 | Pipeline completo: Apps → Manual → Cleanup → Repos → Import-Configs → Finalize              |
| `apps/winget-apps.txt`      | IDs de Winget a instalar, uno por línea, `#` para comentarios                               |
| `apps/winget-remove.txt`    | Denylist de paquetes deprecados: `PackageId \| DisplayNamePattern \| ExtraSilentArgs`       |
| `repos/personal-repos.txt`  | URLs de repos privados a clonar en el perfil del usuario (sólo URLs, nunca credenciales)    |
| `configs/<mod>/`            | `import.ps1` + `README.md` de cada módulo (público: sólo esos dos archivos)                 |
| `scripts/`                  | `Export-*.ps1`, `Install-*.ps1`, `Import-*.ps1`, `Remove-*.ps1`, `Update-*.ps1`, `Menu.ps1` |
| `modules/SetupHelpers.psm1` | Helpers compartidos de consola y Winget                                                     |
| `registry/`                 | `.reg` agrupados para cambios excepcionales (vacío por ahora)                               |
| `docs/`                     | Notas de decisiones y cosas ya probadas                                                     |
| `private-configs/`          | Backups reales. **GIT-IGNORED**                                                             |

Módulos de configuración: `powertoys`, `windows-ui`, `startup`, `terminal`, `wisp`, `git`,
`manual-installs` (manifiesto `apps.json` + docs).

El backup de recuperación es **copiar la carpeta `private-configs/` completa** a un medio externo (USB,
nube, otra PC). No existe script de empaquetado a propósito: nunca dejarla dentro del repo.

El cleanup de apps deprecadas mata los procesos de la app, prueba `winget uninstall --silent` y cae al
uninstaller propio con su switch silencioso (MSI `/qn`, NSIS `/S`, Inno `/VERYSILENT`, Squirrel, familia
Firefox `helper.exe -ms`). `-AllowInteractiveFallback` es el último recurso, opt-in.

**Repos personales.** `repos/personal-repos.txt` lista repos privados (una URL por línea, `#` para
comentarios; `owner/repo` se expande a `https://github.com/owner/repo`). `scripts/Clone-PersonalRepos.ps1`
los clona en `$env:USERPROFILE` usando el último segmento de la URL como nombre de carpeta. Es idempotente
(`git clone` si no existe, `git pull --ff-only` si existe), tolerante (warning + sigue) y soporta `-DryRun`.
Una carpeta con el mismo nombre pero sin `.git` adentro **no se toca**: pisarla puede borrar datos del usuario.
Las credenciales las resuelve **Git Credential Manager** (`credential.helper=manager`, activo a nivel system
con Git for Windows): nunca hay tokens en el repo. El script corre con `GIT_TERMINAL_PROMPT=0` para que un
clone sin credenciales falle rápido en vez de colgar el setup.

## Puntos de entrada y comandos

```powershell
# menú interactivo (vía recomendada, incluye detección de admin y elevación)
.\Menu.cmd

# pipeline completo; soporta -DryRun, -SkipApps, -SkipManual, -SkipCleanup, -SkipRepos, -SkipConfigs, -SkipFinalize
.\Setup.ps1 -DryRun
```

Etapas sueltas:

| Etapa                   | Script                                                                                       | `-DryRun`       |
| ----------------------- | -------------------------------------------------------------------------------------------- | --------------- |
| Instalar Winget         | `scripts/Install-Winget.ps1`                                                                 | —               |
| Instalar apps           | `scripts/Install-Apps.ps1 -RepositoryRoot .`                                                 | sí              |
| Apps manuales           | `scripts/Install-ManualApps.ps1 -RepositoryRoot .` (lee `configs/manual-installs/apps.json`) | sí              |
| Desinstalar deprecados  | `scripts/Remove-DeprecatedApps.ps1 -RepositoryRoot .`                                        | sí              |
| Clonar repos personales | `scripts/Clone-PersonalRepos.ps1 -RepositoryRoot .` (idempotente: clone o pull)              | sí              |
| Importar configs        | `scripts/Import-Configs.ps1 -RepositoryRoot .` (propaga `-DryRun` a todos los importers)     | sí              |
| Actualizar todo         | `scripts/Update-Apps.ps1 -RepositoryRoot .`                                                  | sí (sólo lista) |
| Exportar todo           | opción 5 del menú, o `scripts/Export-<Modulo>.ps1`                                           | —               |
| Finalize                | `scripts/Finalize.ps1 -RepositoryRoot .`                                                     | —               |

### Cambiar el monitor principal (modo trabajo / juego)

`Toggle-Display.cmd` → `scripts/Toggle-PrimaryDisplay.ps1`, que usa **MultiMonitorTool** (NirSoft, portable,
en `%LOCALAPPDATA%\Programs\MultiMonitorTool`). Sirve para tener el Start, los toasts y los flyouts en el
monitor que estás mirando sin dejar de usar el otro para juegos: Windows **siempre** los abre en el primario
y no hay setting que lo cambie.

- `-DryRun` imprime el comando `/SetMonitors` que aplicaría, sin tocar nada.
- Verifica el resultado leyendo la posición de cada monitor **desde el driver** y avisa si quedaron superpuestos.
- **Por qué no se hace con la API de Windows:** `ChangeDisplaySettingsEx` + `CDS_SET_PRIMARY` reposiciona el
  monitor pero nunca le cede la primacía, y el lote con `CDS_NORESET` (la única vía documentada) devuelve
  `DISP_CHANGE_BADFLAGS` (-4) en Windows 11. La herramienta usa `SetDisplayConfig`, que es la API moderna.
- **Bug conocido de Windows 11 24H2:** el propio readme de MultiMonitorTool avisa que _"every action you try
  fails completely"_. Síntoma: `/SetPrimary`, `/SetNextPrimary` y `/SetMonitors` devuelven `0` sin cambiar nada.
  Se destraba cambiando algo en Configuración → Pantalla, o desenchufando y reenchufando un monitor, y
  volviendo a intentar.

`/SetNextPrimary` es la forma más corta de un toggle (rota el primario al siguiente monitor), útil si
`/SetMonitors` resulta frágil en alguna configuración.

El atajo se llama **`Change`** y vive en `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Change.lnk` porque Wisp
sólo puede pinear apps de `shell:AppsFolder`. Ese `.lnk` tiene la ruta absoluta del repo, así que en otra
máquina hay que recrearlo:

```powershell
$ws = New-Object -ComObject WScript.Shell
$sc = $ws.CreateShortcut("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Change.lnk")
$sc.TargetPath = (Join-Path (Get-Location) 'Toggle-Display.cmd')
$sc.WorkingDirectory = (Get-Location).Path
$sc.IconLocation = "$env:SystemRoot\System32\DisplaySwitch.exe"
$sc.WindowStyle = 7
$sc.Save()
```

En el launcher de Wisp aparece buscando `change` (o `cha`), y se puede pinear al dock.

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

Necesitan elevación: cualquier cosa de nivel máquina (`HKLM`, `%ProgramData%`, servicios). Hoy ningún módulo
lo exige de forma obligatoria. El menú detecta si la sesión es admin y ofrece relanzarse elevado. Si un
script descubre que le falta elevación, tiene que **decirlo fuerte y salir limpio** (no fallar a medias).

## Trampas ya resueltas (no reintroducir)

- **Variables de entorno sin filtrar** rompen `TEMP`/`TMP` en el destino y dejan inutilizables los instaladores
  basados en Squirrel/Electron. Denylist obligatoria (`TEMP`, `TMP`, `USERPROFILE`, `APPDATA`, `LOCALAPPDATA`, …)
  y normalización de rutas del perfil a tokens portables.
- **Parser de startup**: cortar el comando en el primer espacio rompe rutas sin comillas con espacios.
  Usar regex sobre la ruta con extensión (`.exe|.bat|.cmd|.lnk|.msc|.com`). Además, filtrar entradas _stale_
  (ejecutable inexistente) al exportar: si en el backup ves una entrada muerta, volvé a correr el export.
- **Importadores que no frenan la app dueña del archivo** escriben y después la app pisa todo al cerrarse.
  Patrón: parar → escribir → volver a arrancar (Wisp).
- **PowerToys**: `backup_restore_settings.json` en `%LOCALAPPDATA%\PowerToys` y el `.ptb` en
  `Documents/PowerToys/Backup` son necesarios para Command Palette y atajos. La visibilidad de íconos de
  bandeja depende de Windows (`HKCU\Control Panel\NotifyIconSettings`), no de PowerToys.
- **`-DryRun` tiene que propagarse** de punta a punta. Un `Setup.ps1 -DryRun` que escribe de verdad es un bug.
- **Apps instaladas fuera de Winget** no aparecen en `winget list`: el cleanup no las ve. Si una app se
  instaló a mano, hay que sacarla a mano o documentarla en `configs/manual-installs/README.md`.

## Estado actual de las decisiones (2026-11)

- **Wisp es la taskbar**: es un dock + launcher (Rust, ~2 MB, sin admin) que oculta
  la taskbar de Windows. Config en `%APPDATA%\wisp\config.toml` (un solo archivo), autostart vía
  `HKCU\...\Run` como `Wisp`. **No tiene paquete en Winget**: instalación manual en
  `%LOCALAPPDATA%\Programs\Wisp`. No tiene botón de Start en el dock (sólo el de búsqueda).
- **FancyZones** cubre "abrir ventanas nuevas en el monitor activo" (`openWindowOnActiveMonitor = true`).
  No hace falta nada más para eso, y tener dos cosas compitiendo rompe el resultado.
- **SoundSwitch es el switcher (2026-11-26).** El primer intento se descartó porque al cambiar de dispositivo,
  sobre todo en juego, la PC parpadeaba y quedaba trabada. El registro de eventos no mostraba ni un `TDR`
  (4101) ni reinicios de `Audiosrv`, así que la causa era el **banner overlay**, no el audio. Con
  notificaciones en `Sound only` y sin triggers está en uso diario sin problemas desde el 2026-11-20.
  Decisiones y descartes en `docs/audio-bluetooth.md`.
- **Audio Bluetooth**: los auriculares exponen `Hands-Free` (mono, calidad de llamada) y A2DP (estéreo).
  La solución de raíz es destildar "Manos libres Telephony" en las propiedades del dispositivo.

## Pendientes conocidos

- Export/import del perfil de Firefox (`Export-Firefox.ps1` + `configs/firefox/import.ps1`).
- Startup a nivel máquina (`HKLM\...\Run` + carpeta Startup común), requiere admin.
- Validar si el toggle de "Manos libres Telephony" alcanza como solución completa de audio.
- `configs/git/README.md` falta (existe el `import.ps1`).
- Validación end-to-end en una segunda máquina después de cada cambio grande.
- Validar el bootstrap de repos en una máquina **limpia**: el flujo ya existe (`repos/personal-repos.txt`),
  pero todavía no se corrió en un Windows recién instalado, donde Git Credential Manager pide auth la
  primera vez. Nunca hardcodear la ruta del usuario.

## Dónde está el detalle

- `README.md` — visión general y quick start.
- `docs/README.md` — índice de notas de decisiones.
- `docs/audio-bluetooth.md` — audio/Bluetooth: qué se probó y por qué.
- `configs/<mod>/README.md` — cada módulo, con sus gotchas.
- `configs/manual-installs/README.md` — apps sin paquete en Winget.
