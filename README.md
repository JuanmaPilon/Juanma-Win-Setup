# Windows Setup 🪟

Personal infrastructure-as-code toolkit for reproducible Windows 11 installs.

It is designed to restore a machine to your preferred state quickly: install apps, import personal configs, and keep sensitive backups private.

## Goals

- Keep the setup idempotent whenever practical.
- Prefer official Microsoft tooling such as PowerShell, Winget, and supported APIs.
- Keep the repository modular and easy to maintain.
- Avoid registry hacks unless there is no supported alternative.

## What this setup restores

- Apps via Winget package list.
- StartAllBack configuration.
- PowerToys configuration.
- Windows UI preferences (mouse and theme settings).
- Environment variables.
- Startup apps (Run entries and Startup folder).

## Repository layout

- apps/: application manifests and Winget package lists
- configs/: application configuration backups and import hooks
- registry/: grouped registry files for exceptional changes
- scripts/: focused PowerShell scripts for setup stages
- modules/: reusable PowerShell helper functions
- docs/: documentation for maintenance and decisions
- backups/: exported settings that are not ideal for version control

## Quick start ⚡

1. Install Git for Windows.
2. Clone this repository.
3. Open PowerShell in the repository root.
4. Run the interactive menu:

   ```powershell
   .\scripts\Menu.ps1
   ```

Alternative launcher:

```powershell
.\Menu.cmd
```

Recommended order on a fresh machine:

1. Install Winget.
2. Run full setup.
3. Import environment variables.
4. Import config backups.

## Notes

The implementation is modular by design. Each script has a focused responsibility so the setup can grow without becoming brittle.

AI agents contributing to this repo should follow [.github/copilot-instructions.md](.github/copilot-instructions.md).

## Backup policy 🔒

Sensitive or machine-specific data should not be committed by default.

- Keep private exports under private-configs/ (Git-ignored).
- Use public folders only for scripts, templates, and documentation.
- Treat registry exports and app snapshots as private unless intentionally sanitized.

## Config coverage ✅

The current setup flow focuses on environment variables, StartAllBack, PowerToys, Windows UI preferences (mouse/theme), and startup apps. Each export uses a private backup path so you can rebuild the same machine state without publishing personal data.

Apps without a Winget package are tracked in [configs/manual-installs/README.md](configs/manual-installs/README.md), with vendor links and instructions to keep installers under `private-configs/manual-installs/`.

## Environment variables safety

Environment variable export/import is hardened for cross-machine portability.

- Windows-managed variables (for example TEMP, TMP, USERPROFILE, APPDATA, LOCALAPPDATA) are skipped by default.
- Paths under user profiles are normalized to portable tokens when possible (for example %USERPROFILE%).
- Unsafe values tied to a different user profile are detected and skipped.
- Import supports preview mode before applying changes.

Preview import without writing changes:

```powershell
.\scripts\Import-EnvironmentVariables.ps1 -DryRun
```

## Typical workflow between desktop and laptop

1. On desktop, run Export everything from the menu.
2. Sync or copy private-configs/ to the target machine securely.
3. On laptop, run the menu and import environment variables and config backups.
4. Restart session if a setting does not apply immediately.
