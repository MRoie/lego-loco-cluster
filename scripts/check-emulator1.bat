@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\check-emulator1.ps1" > scripts\check-emulator1-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\check-emulator1-result.txt
echo DONE >> scripts\check-emulator1-result.txt
echo wrote scripts\check-emulator1-result.txt
