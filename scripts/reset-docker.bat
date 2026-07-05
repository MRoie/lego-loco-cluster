@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\reset-docker.ps1" > scripts\reset-docker-result.txt 2>&1
echo === EXIT: %ERRORLEVEL% === >> scripts\reset-docker-result.txt
echo DONE >> scripts\reset-docker-result.txt
