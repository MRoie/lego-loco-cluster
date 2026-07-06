@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\wiz6.ps1" > scripts\wiz6-result.txt 2>&1
echo DONE >> scripts\wiz6-result.txt
