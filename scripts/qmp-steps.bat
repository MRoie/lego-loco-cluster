@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\qmp-steps.ps1" > scripts\qmp-steps-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\qmp-steps-result.txt
echo DONE >> scripts\qmp-steps-result.txt
