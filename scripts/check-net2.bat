@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\check-net2.ps1" > scripts\check-net2-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\check-net2-result.txt
echo DONE >> scripts\check-net2-result.txt
