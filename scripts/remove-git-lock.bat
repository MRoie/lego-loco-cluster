@echo off
cd /d G:\dev\lego-loco-cluster
if exist .git\index.lock (
  del /f /q .git\index.lock
  echo Removed .git\index.lock
) else (
  echo No lock file present.
)
pause
