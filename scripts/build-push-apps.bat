@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\build-push-apps.ps1" > scripts\build-push-apps-result.txt 2>&1
echo === EXIT: %ERRORLEVEL% === >> scripts\build-push-apps-result.txt
echo DONE >> scripts\build-push-apps-result.txt
