@echo off
cd /d G:\dev\lego-loco-cluster
echo === tagging and pushing milestone aliases === > scripts\milestone-result.txt
set BASE=ghcr.io/mroie/lego-loco-cluster/win98-softgpu
for %%T in (win98-post-softgpu-drivers win98-post-directx-amigamerlin win98-final) do (
  echo --- %%T --- >> scripts\milestone-result.txt
  docker tag %BASE%:latest %BASE%:%%T >> scripts\milestone-result.txt 2>&1
  docker push %BASE%:%%T >> scripts\milestone-result.txt 2>&1
  echo. >> scripts\milestone-result.txt
)
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\milestone-result.txt
echo DONE >> scripts\milestone-result.txt
echo wrote scripts\milestone-result.txt
pause
