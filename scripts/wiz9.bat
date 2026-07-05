@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\wiz9.ps1" > scripts\wiz9-result.txt 2>&1
echo DONE >> scripts\wiz9-result.txt
