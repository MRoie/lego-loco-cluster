@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\dd-pods-check3.ps1" > scripts\dd-pods-check3-result.txt 2>&1
echo DONE >> scripts\dd-pods-check3-result.txt
