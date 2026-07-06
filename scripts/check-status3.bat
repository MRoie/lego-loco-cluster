@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\check-status3.ps1" > scripts\check-status3-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\check-status3-result.txt
echo DONE >> scripts\check-status3-result.txt
echo wrote scripts\check-status3-result.txt
