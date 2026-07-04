@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\create-kind-cluster.ps1" > scripts\create-kind-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\create-kind-result.txt
echo DONE >> scripts\create-kind-result.txt
echo wrote scripts\create-kind-result.txt
pause
