@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\verify-net-single.ps1" > scripts\verify-net-single-result.txt 2>&1
echo DONE >> scripts\verify-net-single-result.txt
