@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\flatten-and-load.ps1" > scripts\flatten-and-load-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\flatten-and-load-result.txt
echo DONE >> scripts\flatten-and-load-result.txt
echo wrote scripts\flatten-and-load-result.txt
pause
