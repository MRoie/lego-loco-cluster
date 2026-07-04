@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\fix-audio.ps1" > scripts\fix-audio-result.txt 2>&1
echo DONE >> scripts\fix-audio-result.txt
