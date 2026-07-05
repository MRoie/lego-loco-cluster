@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\insert-cd.ps1" > scripts\insert-cd-result.txt 2>&1
echo DONE >> scripts\insert-cd-result.txt
