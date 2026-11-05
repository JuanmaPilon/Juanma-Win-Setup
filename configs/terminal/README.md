# Terminal configuration

Restores the terminal look & feel between machines: Windows Terminal, PowerShell profiles, Oh My Posh, fastfetch and completions.

## What it covers

| Pieza | Origen | Destino |
|---|---|---|
| Windows Terminal | `windows-terminal/settings.json` | `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_*\LocalState\settings.json` |
| PowerShell 7 profile | `profiles/PowerShell/Microsoft.PowerShell_profile.ps1` | `Documents\PowerShell\...` |
| Windows PowerShell 5.1 profile | `profiles/WindowsPowerShell/Microsoft.PowerShell_profile.ps1` | `Documents\WindowsPowerShell\...` |
| Temas Oh My Posh | `oh-my-posh/*.omp.json` | `~\.config\oh-my-posh\` |
| Completions | `completions/*.ps1` | `~\.config\powershell\completions\` |
| fastfetch | `fastfetch/config.jsonc` | `%APPDATA%\fastfetch\config.jsonc` |

## Dependencias (Winget)

```
JanDeDobbeleer.OhMyPosh
DEVCOM.JetBrainsMonoNerdFont
Fastfetch-cli.Fastfetch
svenstaro.genact
cowboy8625.rusty-rain
```

`Terminal-Icons` es un módulo de PowerShell (no Winget). El importador intenta instalarlo automáticamente si falta.

En Windows PowerShell 5.1 hace falta PSReadLine >= 2.1 para sugerencias predictivas:

```powershell
Install-Module PSReadLine -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber
```

## Flujo

1. En la PC principal: `Export everything` desde el menú (o `scripts\Export-TerminalConfig.ps1`).
2. Copiar `private-configs/terminal` a la máquina destino.
3. Importar (menú → Import config backups, o `configs\terminal\import.ps1 -RepositoryRoot <repo> -DryRun` para previsualizar).

## Notas

- El importador hace **backup automático** de los archivos que reemplaza (`*.bak-<timestamp>`).
- `settings.json` de Windows Terminal es portable entre máquinas con la misma versión mayor de Terminal; si el destino tiene otra versión, revisá colores/fuente tras importar.
- Los profiles usan rutas relativas a `$HOME`, así que funcionan con cualquier nombre de usuario.
