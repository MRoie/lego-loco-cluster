@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\gh-check.ps1" > scripts\gh-check-result.txt 2>&1
echo DONE >> scripts\gh-check-result.txt
