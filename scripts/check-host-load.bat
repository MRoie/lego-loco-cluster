@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\check-host-load.ps1" > scripts\check-host-load-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\check-host-load-result.txt
echo DONE >> scripts\check-host-load-result.txt
echo wrote scripts\check-host-load-result.txt
