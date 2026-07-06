@echo off
cd /d G:\dev\lego-loco-cluster
echo === docker images === > scripts\images-check.txt
docker images >> scripts\images-check.txt 2>&1
echo. >> scripts\images-check.txt
echo === minikube version === >> scripts\images-check.txt
minikube version >> scripts\images-check.txt 2>&1
echo. >> scripts\images-check.txt
echo === minikube status === >> scripts\images-check.txt
minikube status >> scripts\images-check.txt 2>&1
echo. >> scripts\images-check.txt
echo === docker context ls === >> scripts\images-check.txt
docker context ls >> scripts\images-check.txt 2>&1
echo DONE >> scripts\images-check.txt
echo wrote scripts\images-check.txt
pause
