@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\finish-rebuild.ps1" > scripts\finish-rebuild-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\finish-rebuild-result.txt
echo DONE >> scripts\finish-rebuild-result.txt
echo wrote scripts\finish-rebuild-result.txt
