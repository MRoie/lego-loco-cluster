@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\fix-storage-upgrade.ps1" > scripts\fix-storage-upgrade-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\fix-storage-upgrade-result.txt
echo DONE >> scripts\fix-storage-upgrade-result.txt
echo wrote scripts\fix-storage-upgrade-result.txt
pause
