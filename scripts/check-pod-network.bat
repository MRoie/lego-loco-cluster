@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\check-pod-network.ps1" > scripts\check-pod-network-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\check-pod-network-result.txt
echo DONE >> scripts\check-pod-network-result.txt
echo wrote scripts\check-pod-network-result.txt
