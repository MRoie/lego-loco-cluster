@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\assess-state.ps1" > scripts\assess-state-result.txt 2>&1
echo === EXIT: %ERRORLEVEL% === >> scripts\assess-state-result.txt
echo DONE >> scripts\assess-state-result.txt
