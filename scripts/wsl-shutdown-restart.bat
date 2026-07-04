@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\wsl-shutdown-restart.ps1" > scripts\wsl-shutdown-restart-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\wsl-shutdown-restart-result.txt
echo DONE >> scripts\wsl-shutdown-restart-result.txt
echo wrote scripts\wsl-shutdown-restart-result.txt
pause
