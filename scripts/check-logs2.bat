@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\check-logs2.ps1" > scripts\check-logs2-result.txt 2>&1
echo DONE >> scripts\check-logs2-result.txt
