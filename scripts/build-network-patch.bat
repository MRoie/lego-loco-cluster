@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\build-network-patch.ps1" > scripts\build-network-patch-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\build-network-patch-result.txt
echo DONE >> scripts\build-network-patch-result.txt
echo wrote scripts\build-network-patch-result.txt
pause
