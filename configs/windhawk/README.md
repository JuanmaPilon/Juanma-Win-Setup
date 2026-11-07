# Windhawk configuration (portable)

Restaura la configuración de **Windhawk en modo portable** (sin registro, sin ProgramData).

## Requisitos

Windhawk instalado en modo portable:

```powershell
windhawk_setup.exe /S /PORTABLE /D=$env:LOCALAPPDATA\Programs\Windhawk
```

El importador solo soporta modo portable (`windhawk.ini` con `[Storage] Portable=1`).

## Qué exporta/importa

| Ruta | Contenido |
|---|---|
| `AppData\settings.ini` | settings de la app (tema, idioma, etc.) |
| `AppData\Engine\settings.ini` | settings del engine (include/exclude de procesos) |
| `AppData\Engine\Mods\*.ini` | settings de cada mod instalado |
| `AppData\ModsSource\*.wh.cpp` | fuentes de los mods instalados |

Se excluye `Symbols\` (caché) y `warning.txt`.

## Flujo en una PC nueva

1. Instalar Windhawk portable (comando de arriba).
2. Abrirlo una vez y dejar que descargue el engine.
3. Importar (menú → Import config backups, o `configs\windhawk\import.ps1 -RepositoryRoot <repo>`).
4. Abrir Windhawk de nuevo: los mods recompilan solos desde `ModsSource`.

## Mods recomendados para taskbar

Buscar en el catálogo de Windhawk (pestaña "Explore"):

- **Taskbar height and icon size** → altura de la taskbar e íconos.
- **Taskbar tray icon spacing and grid** → tamaño/espaciado de los íconos de la bandeja.

## Advertencias

- No activar "inyectar en juegos" si usás juegos con anti-cheat (Vanguard/LoL).
- Los mods se actualizan desde el catálogo; una update puede cambiar el esquema de settings.
- Los binarios del engine no se respaldan (se reinstalan con el instalador); solo viaja la configuración.
