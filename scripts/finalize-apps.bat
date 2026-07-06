@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\finalize-apps.ps1" > scripts\finalize-apps-result.txt 2>&1
echo === EXIT: %ERRORLEVEL% === >> scripts\finalize-apps-result.txt
echo DONE >> scripts\finalize-apps-result.txt
