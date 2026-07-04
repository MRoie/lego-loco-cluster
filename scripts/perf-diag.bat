@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\perf-diag.ps1" > scripts\perf-diag-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\perf-diag-result.txt
echo DONE >> scripts\perf-diag-result.txt
echo wrote scripts\perf-diag-result.txt
