@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\git-commit-push.ps1" > scripts\git-commit-push-result.txt 2>&1
echo === EXIT: %ERRORLEVEL% === >> scripts\git-commit-push-result.txt
echo DONE >> scripts\git-commit-push-result.txt
