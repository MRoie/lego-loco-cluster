@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\docker-health.ps1" > scripts\docker-health3-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\docker-health3-result.txt
echo DONE >> scripts\docker-health3-result.txt
echo wrote scripts\docker-health3-result.txt
pause
