@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\push-check2.ps1" > scripts\push-check2-result.txt 2>&1
echo DONE >> scripts\push-check2-result.txt
