@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\dd-pods-check2.ps1" > scripts\dd-pods-check2-result.txt 2>&1
echo DONE >> scripts\dd-pods-check2-result.txt
