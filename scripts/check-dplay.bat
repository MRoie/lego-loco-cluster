@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\check-dplay.ps1" > scripts\check-dplay-result.txt 2>&1
echo DONE >> scripts\check-dplay-result.txt
