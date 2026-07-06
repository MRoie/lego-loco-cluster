@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\kprobe.ps1" > scripts\kprobe-result.txt 2>&1
echo DONE >> scripts\kprobe-result.txt
