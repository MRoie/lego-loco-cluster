@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\deploy-dd-single.ps1" > scripts\deploy-dd-single-result.txt 2>&1
echo DONE >> scripts\deploy-dd-single-result.txt
