@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\redeploy-frontend2.ps1" > scripts\redeploy-frontend2-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\redeploy-frontend2-result.txt
echo DONE >> scripts\redeploy-frontend2-result.txt
echo wrote scripts\redeploy-frontend2-result.txt
pause
