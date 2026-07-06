@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\verify-net3.ps1" > scripts\verify-net3-result.txt 2>&1
echo === EXIT: %ERRORLEVEL% === >> scripts\verify-net3-result.txt
echo DONE >> scripts\verify-net3-result.txt
