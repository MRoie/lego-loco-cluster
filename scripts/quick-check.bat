@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\quick-check.ps1" > scripts\quick-check-result.txt 2>&1
echo DONE >> scripts\quick-check-result.txt
