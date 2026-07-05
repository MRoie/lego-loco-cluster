@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\dwsl-inspect.ps1" > scripts\dwsl-inspect-result.txt 2>&1
echo === EXIT: %ERRORLEVEL% === >> scripts\dwsl-inspect-result.txt
echo DONE >> scripts\dwsl-inspect-result.txt
