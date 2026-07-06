@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\check-kvm.ps1" > scripts\check-kvm-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\check-kvm-result.txt
echo DONE >> scripts\check-kvm-result.txt
echo wrote scripts\check-kvm-result.txt
