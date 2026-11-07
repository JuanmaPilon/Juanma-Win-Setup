@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Menu.ps1"
if errorlevel 1 (
    echo.
    echo [setup] The menu exited with an error. Review the messages above.
    pause
)
endlocal
