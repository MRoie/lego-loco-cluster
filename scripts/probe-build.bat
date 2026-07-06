@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\probe-build.ps1" > scripts\probe-build-result.txt 2>&1
echo DONE >> scripts\probe-build-result.txt
