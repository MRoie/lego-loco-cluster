@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\check-entrypoint.ps1" > scripts\check-entrypoint-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\check-entrypoint-result.txt
echo DONE >> scripts\check-entrypoint-result.txt
echo wrote scripts\check-entrypoint-result.txt
pause
