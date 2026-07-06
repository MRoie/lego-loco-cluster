@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\start-docker.ps1" > scripts\start-docker-result.txt 2>&1
echo === EXIT: %ERRORLEVEL% === >> scripts\start-docker-result.txt
echo DONE >> scripts\start-docker-result.txt
