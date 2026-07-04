@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\check-status.ps1" > scripts\check-status-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\check-status-result.txt
echo DONE >> scripts\check-status-result.txt
echo wrote scripts\check-status-result.txt
pause
