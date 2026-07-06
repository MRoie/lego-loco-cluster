@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\check-export-progress.ps1" > scripts\check-export-progress-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\check-export-progress-result.txt
echo DONE >> scripts\check-export-progress-result.txt
echo wrote scripts\check-export-progress-result.txt
