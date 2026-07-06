@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\deploy-lan-test.ps1" > scripts\deploy-lan-test-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\deploy-lan-test-result.txt
echo DONE >> scripts\deploy-lan-test-result.txt
echo wrote scripts\deploy-lan-test-result.txt
pause
