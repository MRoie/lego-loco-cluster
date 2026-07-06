@echo off
cd /d G:\dev\lego-loco-cluster
start "loco-pf" /min powershell -ExecutionPolicy Bypass -File "scripts\pf-frontend-loop.ps1" > scripts\pf-frontend-loop-result.txt 2>&1
echo started detached port-forward loop
