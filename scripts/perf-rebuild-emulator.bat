@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\perf-rebuild-emulator.ps1" > scripts\perf-rebuild-emulator-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\perf-rebuild-emulator-result.txt
echo DONE >> scripts\perf-rebuild-emulator-result.txt
echo wrote scripts\perf-rebuild-emulator-result.txt
