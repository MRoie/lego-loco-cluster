@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\check-mesh.ps1" > scripts\check-mesh-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\check-mesh-result.txt
echo DONE >> scripts\check-mesh-result.txt
echo wrote scripts\check-mesh-result.txt
pause
