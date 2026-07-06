@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\redeploy-emulator-final.ps1" > scripts\redeploy-emulator-final-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\redeploy-emulator-final-result.txt
echo DONE >> scripts\redeploy-emulator-final-result.txt
echo wrote scripts\redeploy-emulator-final-result.txt
pause
