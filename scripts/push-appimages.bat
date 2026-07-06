@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\push-appimages.ps1" > scripts\push-appimages-result.txt 2>&1
echo === EXIT: %ERRORLEVEL% === >> scripts\push-appimages-result.txt
echo DONE >> scripts\push-appimages-result.txt
