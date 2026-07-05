@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\build-push-snapshot.ps1" > scripts\build-push-snapshot-result.txt 2>&1
echo DONE >> scripts\build-push-snapshot-result.txt
