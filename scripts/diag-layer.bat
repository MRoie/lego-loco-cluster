@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\diag-layer.ps1" > scripts\diag-layer-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\diag-layer-result.txt
echo DONE >> scripts\diag-layer-result.txt
echo wrote scripts\diag-layer-result.txt
pause
