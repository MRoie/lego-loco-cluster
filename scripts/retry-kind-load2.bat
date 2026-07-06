@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\retry-kind-load2.ps1" > scripts\retry-kind-load2-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\retry-kind-load2-result.txt
echo DONE >> scripts\retry-kind-load2-result.txt
echo wrote scripts\retry-kind-load2-result.txt
pause
