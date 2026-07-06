@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\wiz8.ps1" > scripts\wiz8-result.txt 2>&1
echo DONE >> scripts\wiz8-result.txt
