@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\ghcr-inventory.ps1" > scripts\ghcr-inventory-result.txt 2>&1
echo DONE >> scripts\ghcr-inventory-result.txt
