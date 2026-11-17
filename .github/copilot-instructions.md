# Copilot / agent instructions

**La fuente de verdad de este repo es [`/AGENTS.md`](../AGENTS.md).** Leelo antes de tocar nada.
Este archivo existe sólo para que las herramientas que buscan `.github/copilot-instructions.md`
lleguen al documento correcto, y para dejar a mano las reglas que nunca se pueden saltear.

## Reglas críticas

1. `private-configs/` **nunca** se commitea: tiene datos personales y está en `.gitignore`.
2. **Nunca** hardcodear `C:\Users\<usuario>`: usar `$env:USERPROFILE`, `%APPDATA%`, `%LOCALAPPDATA%`,
   `%ProgramData%`. Todo tiene que funcionar con otro nombre de usuario.
3. Todo tiene que ser **idempotente** y modular (un script = una responsabilidad).
4. Mensajes de consola **sólo** por `modules/SetupHelpers.psm1`; los importadores lo importan con `-Force`.
5. Exportadores con `$ErrorActionPreference = 'Stop'`; importadores con `'Continue'` y tolerantes.
6. Ningún mod de Windhawk con `Include = *` (inyecta el DLL en todos los procesos y crashea juegos).
7. `-DryRun` tiene que propagarse de punta a punta y no escribir nada.
8. Nunca commitear instaladores, claves de licencia, seriales ni tokens.

## Antes de dar un cambio por terminado

```powershell
# sintaxis
$e = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\Setup.ps1), [ref]$null, [ref]$e)
$e.Count   # tiene que dar 0

# pipeline en seco
.\Setup.ps1 -DryRun -SkipApps -SkipCleanup -SkipFinalize
```

Si tocaste un exportador, corrélo de verdad y confirmá que los archivos aparecen en `private-configs/<mod>`.

Para el checklist de módulos nuevos, el mapa del repo, las trampas ya resueltas y los pendientes:
todo está en [`/AGENTS.md`](../AGENTS.md).
