@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\push-existing.ps1" > scripts\push-existing-result.txt 2>&1
echo === EXIT: %ERRORLEVEL% === >> scripts\push-existing-result.txt
echo DONE >> scripts\push-existing-result.txt
