@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\git-inspect.ps1" > scripts\git-inspect-result.txt 2>&1
echo DONE >> scripts\git-inspect-result.txt
