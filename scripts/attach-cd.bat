@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\attach-cd.ps1" > scripts\attach-cd-result.txt 2>&1
echo DONE >> scripts\attach-cd-result.txt
