@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\standalone-run.ps1" > scripts\standalone-run-result.txt 2>&1
echo === EXIT: %ERRORLEVEL% === >> scripts\standalone-run-result.txt
echo DONE >> scripts\standalone-run-result.txt
