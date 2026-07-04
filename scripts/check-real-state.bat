@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\check-real-state.ps1" > scripts\check-real-state-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\check-real-state-result.txt
echo DONE >> scripts\check-real-state-result.txt
echo wrote scripts\check-real-state-result.txt
