@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\rebuild1-emulator-image.ps1" > scripts\rebuild1-result.txt 2>&1
echo === EXIT: %ERRORLEVEL% === >> scripts\rebuild1-result.txt
echo DONE >> scripts\rebuild1-result.txt
