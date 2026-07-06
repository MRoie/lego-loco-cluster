@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\kind-cleanup.ps1" > scripts\kind-cleanup-result.txt 2>&1
echo DONE >> scripts\kind-cleanup-result.txt
