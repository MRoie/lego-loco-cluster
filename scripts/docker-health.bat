@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\docker-health.ps1" > scripts\docker-health-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\docker-health-result.txt
echo DONE >> scripts\docker-health-result.txt
echo wrote scripts\docker-health-result.txt
pause
