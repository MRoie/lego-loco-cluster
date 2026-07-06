@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\health2.ps1" > scripts\health2-result.txt 2>&1
echo === EXIT: %ERRORLEVEL% === >> scripts\health2-result.txt
echo DONE >> scripts\health2-result.txt
