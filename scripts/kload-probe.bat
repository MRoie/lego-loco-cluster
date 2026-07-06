@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\kload-probe.ps1" > scripts\kload-probe-result.txt 2>&1
echo DONE >> scripts\kload-probe-result.txt
