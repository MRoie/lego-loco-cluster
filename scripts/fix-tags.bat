@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\fix-tags.ps1" > scripts\fix-tags-result.txt 2>&1
echo DONE >> scripts\fix-tags-result.txt
