@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\check-proc.ps1" > scripts\check-proc-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\check-proc-result.txt
echo DONE >> scripts\check-proc-result.txt
echo wrote scripts\check-proc-result.txt
