@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\wiz1.ps1" > scripts\wiz1-result.txt 2>&1
echo DONE >> scripts\wiz1-result.txt
