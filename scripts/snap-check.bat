@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\snap-check.ps1" > scripts\snap-check-result.txt 2>&1
echo DONE >> scripts\snap-check-result.txt
