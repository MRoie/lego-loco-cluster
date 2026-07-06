@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\bbk.ps1" > scripts\bbk-result.txt 2>&1
echo === EXIT: %ERRORLEVEL% === >> scripts\bbk-result.txt
echo DONE >> scripts\bbk-result.txt
