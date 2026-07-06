@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\check-import-cpu.ps1" > scripts\check-import-cpu-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\check-import-cpu-result.txt
echo DONE >> scripts\check-import-cpu-result.txt
echo wrote scripts\check-import-cpu-result.txt
