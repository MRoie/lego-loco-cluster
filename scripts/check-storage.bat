@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\check-storage.ps1" > scripts\check-storage-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\check-storage-result.txt
echo DONE >> scripts\check-storage-result.txt
