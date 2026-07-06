@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\kill-stuck.ps1" > scripts\kill-stuck-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\kill-stuck-result.txt
echo DONE >> scripts\kill-stuck-result.txt
echo wrote scripts\kill-stuck-result.txt
pause
