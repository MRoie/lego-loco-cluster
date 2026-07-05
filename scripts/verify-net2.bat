@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\verify-net2.ps1" > scripts\verify-net2-result.txt 2>&1
echo DONE >> scripts\verify-net2-result.txt
