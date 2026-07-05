@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\salvage.ps1" > scripts\salvage-result.txt 2>&1
echo === EXIT: %ERRORLEVEL% === >> scripts\salvage-result.txt
echo DONE >> scripts\salvage-result.txt
