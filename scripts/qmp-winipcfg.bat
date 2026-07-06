@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\qmp-winipcfg.ps1" > scripts\qmp-winipcfg-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\qmp-winipcfg-result.txt
echo DONE >> scripts\qmp-winipcfg-result.txt
