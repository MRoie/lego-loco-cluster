@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\free-disk-space.ps1" > scripts\free-disk-space-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\free-disk-space-result.txt
echo DONE >> scripts\free-disk-space-result.txt
echo wrote scripts\free-disk-space-result.txt
pause
