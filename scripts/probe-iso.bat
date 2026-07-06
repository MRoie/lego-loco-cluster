@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\probe-iso.ps1" > scripts\probe-iso-result.txt 2>&1
echo DONE >> scripts\probe-iso-result.txt
