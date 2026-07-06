@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\wiz7.ps1" > scripts\wiz7-result.txt 2>&1
echo DONE >> scripts\wiz7-result.txt
