@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\check-kind-cpu.ps1" > scripts\check-kind-cpu-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\check-kind-cpu-result.txt
echo DONE >> scripts\check-kind-cpu-result.txt
echo wrote scripts\check-kind-cpu-result.txt
