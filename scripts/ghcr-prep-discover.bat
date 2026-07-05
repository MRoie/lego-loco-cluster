@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\ghcr-prep-discover.ps1" > scripts\ghcr-prep-discover-result.txt 2>&1
echo DONE >> scripts\ghcr-prep-discover-result.txt
