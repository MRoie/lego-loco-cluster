@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\port-forward-frontend.ps1" > scripts\port-forward-frontend-result.txt 2>&1
