@echo off
cd /d G:\dev\lego-loco-cluster
echo === docker version === > scripts\cluster-env.txt
docker version >> scripts\cluster-env.txt 2>&1
echo. >> scripts\cluster-env.txt
echo === kubectl version === >> scripts\cluster-env.txt
kubectl version --client >> scripts\cluster-env.txt 2>&1
echo. >> scripts\cluster-env.txt
echo === kind version === >> scripts\cluster-env.txt
kind version >> scripts\cluster-env.txt 2>&1
echo. >> scripts\cluster-env.txt
echo === helm version === >> scripts\cluster-env.txt
helm version >> scripts\cluster-env.txt 2>&1
echo. >> scripts\cluster-env.txt
echo === existing kind clusters === >> scripts\cluster-env.txt
kind get clusters >> scripts\cluster-env.txt 2>&1
echo. >> scripts\cluster-env.txt
echo === kubectl contexts === >> scripts\cluster-env.txt
kubectl config get-contexts >> scripts\cluster-env.txt 2>&1
echo. >> scripts\cluster-env.txt
echo === current nodes (if any context works) === >> scripts\cluster-env.txt
kubectl get nodes -o wide >> scripts\cluster-env.txt 2>&1
echo. >> scripts\cluster-env.txt
echo === wsl status === >> scripts\cluster-env.txt
wsl -l -v >> scripts\cluster-env.txt 2>&1
echo. >> scripts\cluster-env.txt
echo DONE >> scripts\cluster-env.txt
echo wrote scripts\cluster-env.txt
pause
