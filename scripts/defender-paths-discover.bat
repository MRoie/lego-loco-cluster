@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\defender-paths-discover.ps1" > scripts\defender-paths-discover-result.txt 2>&1
echo DONE >> scripts\defender-paths-discover-result.txt
