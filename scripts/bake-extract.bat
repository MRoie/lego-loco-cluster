@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\bake-extract.ps1" > scripts\bake-extract-result.txt 2>&1
echo === EXIT: %ERRORLEVEL% === >> scripts\bake-extract-result.txt
echo DONE >> scripts\bake-extract-result.txt
