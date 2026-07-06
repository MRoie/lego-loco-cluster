@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\check-kindload.ps1" > scripts\check-kindload-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\check-kindload-result.txt
echo DONE >> scripts\check-kindload-result.txt
echo wrote scripts\check-kindload-result.txt
