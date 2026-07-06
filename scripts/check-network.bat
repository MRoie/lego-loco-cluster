@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\check-network.ps1" > scripts\check-network-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\check-network-result.txt
echo DONE >> scripts\check-network-result.txt
echo wrote scripts\check-network-result.txt
pause
