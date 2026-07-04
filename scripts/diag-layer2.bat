@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\diag-layer2.ps1" > scripts\diag-layer2-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\diag-layer2-result.txt
echo DONE >> scripts\diag-layer2-result.txt
echo wrote scripts\diag-layer2-result.txt
pause
