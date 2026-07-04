@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\check-mem.ps1" > scripts\check-mem-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\check-mem-result.txt
echo DONE >> scripts\check-mem-result.txt
echo wrote scripts\check-mem-result.txt
