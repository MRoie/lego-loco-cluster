@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\kload-kill.ps1" > scripts\kload-kill-result.txt 2>&1
echo DONE >> scripts\kload-kill-result.txt
