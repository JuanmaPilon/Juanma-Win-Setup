@echo off
REM Toggles the primary display (work mode <-> game mode).
REM Target for the dock shortcut. Runs hidden; the visible feedback is the screens swapping.
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0scripts\Toggle-PrimaryDisplay.ps1"
