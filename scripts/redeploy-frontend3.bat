@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\redeploy-frontend3.ps1" > scripts\redeploy-frontend3-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\redeploy-frontend3-result.txt
echo DONE >> scripts\redeploy-frontend3-result.txt
echo wrote scripts\redeploy-frontend3-result.txt
pause
