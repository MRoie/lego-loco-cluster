@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\kload-check2.ps1" > scripts\kload-check2-result.txt 2>&1
echo DONE >> scripts\kload-check2-result.txt
