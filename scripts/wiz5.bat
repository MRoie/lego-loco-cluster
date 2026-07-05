@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\wiz5.ps1" > scripts\wiz5-result.txt 2>&1
echo DONE >> scripts\wiz5-result.txt
