@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\redeploy-backend.ps1" > scripts\redeploy-backend-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\redeploy-backend-result.txt
echo DONE >> scripts\redeploy-backend-result.txt
echo wrote scripts\redeploy-backend-result.txt
