@echo off
REM Double-click launcher for win98-softgpu-autorun.ps1
REM No keyboard input required after launch - safe to run via double-click.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0win98-softgpu-autorun.ps1"
echo.
echo Done. You can close this window.
pause
