@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\push-check.ps1" > scripts\push-check-result.txt 2>&1
echo DONE >> scripts\push-check-result.txt
