@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\wiz-step.ps1" %* > scripts\wiz-step-result.txt 2>&1
echo DONE >> scripts\wiz-step-result.txt
