# Documentation

This directory will hold the decision records and maintenance notes for this repository.

## Suggested topics

- How to add a new application
- How to document a registry change
- How to update a configuration backup
- How to keep the setup process idempotent

## Existing notes

- [audio-bluetooth.md](audio-bluetooth.md) — perfil Hands-Free de auriculares Bluetooth, toasts en el monitor equivocado, el protocolo de reintento de SoundSwitch y las herramientas evaluadas.

## Notes on Winget bootstrap

On Windows LTSC or other minimal installs, Winget may not be present initially. The setup flow now attempts to bootstrap it automatically by installing the required PowerShell package provider and the Microsoft.WinGet.Client module before repairing the package manager.
