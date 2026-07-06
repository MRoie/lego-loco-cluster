@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\fix-probes.ps1" > scripts\fix-probes-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\fix-probes-result.txt
echo DONE >> scripts\fix-probes-result.txt
echo wrote scripts\fix-probes-result.txt
