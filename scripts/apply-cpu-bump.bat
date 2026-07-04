@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\apply-cpu-bump.ps1" > scripts\apply-cpu-bump-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\apply-cpu-bump-result.txt
echo DONE >> scripts\apply-cpu-bump-result.txt
echo wrote scripts\apply-cpu-bump-result.txt
