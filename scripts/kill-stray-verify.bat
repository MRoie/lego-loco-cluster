@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\kill-stray-verify.ps1" > scripts\kill-stray-verify-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\kill-stray-verify-result.txt
echo DONE >> scripts\kill-stray-verify-result.txt
echo wrote scripts\kill-stray-verify-result.txt
