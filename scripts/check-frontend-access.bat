@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\check-frontend-access.ps1" > scripts\check-frontend-access-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\check-frontend-access-result.txt
echo DONE >> scripts\check-frontend-access-result.txt
echo wrote scripts\check-frontend-access-result.txt
