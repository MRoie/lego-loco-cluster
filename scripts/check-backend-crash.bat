@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\check-backend-crash.ps1" > scripts\check-backend-crash-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\check-backend-crash-result.txt
echo DONE >> scripts\check-backend-crash-result.txt
echo wrote scripts\check-backend-crash-result.txt
