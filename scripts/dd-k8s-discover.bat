@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\dd-k8s-discover.ps1" > scripts\dd-k8s-discover-result.txt 2>&1
echo DONE >> scripts\dd-k8s-discover-result.txt
