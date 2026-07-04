@echo off
cd /d G:\dev\lego-loco-cluster
echo === publish rebuild qcow2 started at %DATE% %TIME% === > scripts\publish-result.txt
powershell -ExecutionPolicy Bypass -File "scripts\publish-rebuild-qcow2.ps1" >> scripts\publish-result.txt 2>&1
echo. >> scripts\publish-result.txt
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\publish-result.txt
echo DONE >> scripts\publish-result.txt
echo wrote scripts\publish-result.txt
pause
