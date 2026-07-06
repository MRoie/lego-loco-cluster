@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\force-recreate.ps1" > scripts\force-recreate-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\force-recreate-result.txt
echo DONE >> scripts\force-recreate-result.txt
echo wrote scripts\force-recreate-result.txt
pause
