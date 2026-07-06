@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\reset-vms.ps1" > scripts\reset-vms-result.txt 2>&1
echo DONE >> scripts\reset-vms-result.txt
