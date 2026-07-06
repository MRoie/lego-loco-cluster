@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\bake-prep.ps1" > scripts\bake-prep-result.txt 2>&1
echo === EXIT: %ERRORLEVEL% === >> scripts\bake-prep-result.txt
echo DONE >> scripts\bake-prep-result.txt
