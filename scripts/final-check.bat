@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\final-check.ps1" > scripts\final-check-result.txt 2>&1
echo DONE >> scripts\final-check-result.txt
