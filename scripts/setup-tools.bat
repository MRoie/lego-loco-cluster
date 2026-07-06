@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\setup-tools.ps1" > scripts\setup-tools-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\setup-tools-result.txt
echo DONE >> scripts\setup-tools-result.txt
echo wrote scripts\setup-tools-result.txt
pause
