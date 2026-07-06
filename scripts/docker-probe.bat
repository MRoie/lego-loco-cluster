@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\docker-probe.ps1" > scripts\docker-probe-result.txt 2>&1
echo DONE >> scripts\docker-probe-result.txt
