@echo off
cd /d "%~dp0.."
powershell -ExecutionPolicy Bypass -File "scripts\publish-rebuild-qcow2.ps1"
echo.
echo === DONE (exit code %ERRORLEVEL%) ===
pause
