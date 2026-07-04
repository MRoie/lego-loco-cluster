@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\apply-win98cd2.ps1" > scripts\apply-win98cd2-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\apply-win98cd2-result.txt
echo DONE >> scripts\apply-win98cd2-result.txt
