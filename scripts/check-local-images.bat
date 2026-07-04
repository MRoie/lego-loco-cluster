@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\check-local-images.ps1" > scripts\check-local-images-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\check-local-images-result.txt
echo DONE >> scripts\check-local-images-result.txt
echo wrote scripts\check-local-images-result.txt
pause
