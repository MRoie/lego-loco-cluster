@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\bake-extract2.ps1" > scripts\bake-extract2-result.txt 2>&1
echo === EXIT: %ERRORLEVEL% === >> scripts\bake-extract2-result.txt
echo DONE >> scripts\bake-extract2-result.txt
