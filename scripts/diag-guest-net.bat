@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\diag-guest-net.ps1" > scripts\diag-guest-net-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\diag-guest-net-result.txt
echo DONE >> scripts\diag-guest-net-result.txt
echo wrote scripts\diag-guest-net-result.txt
