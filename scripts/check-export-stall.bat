@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\check-export-stall.ps1" > scripts\check-export-stall-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\check-export-stall-result.txt
echo DONE >> scripts\check-export-stall-result.txt
echo wrote scripts\check-export-stall-result.txt
