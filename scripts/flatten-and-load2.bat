@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\flatten-and-load2.ps1" > scripts\flatten-and-load2-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\flatten-and-load2-result.txt
echo DONE >> scripts\flatten-and-load2-result.txt
echo wrote scripts\flatten-and-load2-result.txt
pause
