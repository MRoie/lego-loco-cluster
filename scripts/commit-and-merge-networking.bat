@echo off
cd /d G:\dev\lego-loco-cluster
echo === Removing any stale lock ===
if exist .git\index.lock del /f /q .git\index.lock
echo.
echo === git status before ===
git status --short
echo.
echo === staging script fixes + gitignore ===
git add -A -- scripts .gitignore
git status --short
echo.
echo === committing ===
git commit -m "Fix publish_new_qcow2.ps1 builtin-images path bug; add Win98 rebuild automation scripts"
echo.
echo === fetching latest from origin ===
git fetch origin
echo.
echo === merging origin/feature/pi-dev-agent-teams (guest L2 mesh networking fix) ===
git merge origin/feature/pi-dev-agent-teams --no-edit
echo.
echo === EXIT CODE: %ERRORLEVEL% ===
echo === final status ===
git status --short
pause
