@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\check-mesh-detail.ps1" > scripts\check-mesh-detail-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\check-mesh-detail-result.txt
echo DONE >> scripts\check-mesh-detail-result.txt
echo wrote scripts\check-mesh-detail-result.txt
