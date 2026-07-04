@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\check-daemon-health.ps1" > scripts\check-daemon-health-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\check-daemon-health-result.txt
echo DONE >> scripts\check-daemon-health-result.txt
echo wrote scripts\check-daemon-health-result.txt
