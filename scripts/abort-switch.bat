@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\abort-switch.ps1" > scripts\abort-switch-result.txt 2>&1
echo === EXIT: %ERRORLEVEL% === >> scripts\abort-switch-result.txt
echo DONE >> scripts\abort-switch-result.txt
