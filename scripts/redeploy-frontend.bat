@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\redeploy-frontend.ps1" > scripts\redeploy-frontend-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\redeploy-frontend-result.txt
echo DONE >> scripts\redeploy-frontend-result.txt
echo wrote scripts\redeploy-frontend-result.txt
pause
