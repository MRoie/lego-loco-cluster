@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\tag-push-extra.ps1" > scripts\tag-push-extra-result.txt 2>&1
echo DONE >> scripts\tag-push-extra-result.txt
