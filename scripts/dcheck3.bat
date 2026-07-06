@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\dcheck3.ps1" > scripts\dcheck3-result.txt 2>&1
echo === EXIT: %ERRORLEVEL% === >> scripts\dcheck3-result.txt
echo DONE >> scripts\dcheck3-result.txt
