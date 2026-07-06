@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\free-disk-space2.ps1" > scripts\free-disk-space2-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\free-disk-space2-result.txt
echo DONE >> scripts\free-disk-space2-result.txt
echo wrote scripts\free-disk-space2-result.txt
pause
