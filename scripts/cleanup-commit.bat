@echo off
cd /d G:\dev\lego-loco-cluster
echo === status before === > scripts\cleanup-result.txt
git status --short >> scripts\cleanup-result.txt 2>&1
echo. >> scripts\cleanup-result.txt
echo === adding gitignore rule for script debug output === >> scripts\cleanup-result.txt
findstr /c:"scripts/*-result.txt" .gitignore >nul 2>&1
if errorlevel 1 (
  echo. >> .gitignore
  echo # Transient debug output from helper scripts >> .gitignore
  echo scripts/*-result.txt >> .gitignore
  echo scripts/merge-status.txt >> .gitignore
)
git add .gitignore scripts\publish-rebuild-logged.bat >> scripts\cleanup-result.txt 2>&1
git status --short >> scripts\cleanup-result.txt 2>&1
echo. >> scripts\cleanup-result.txt
echo === committing === >> scripts\cleanup-result.txt
git commit -m "Add logged publish wrapper; gitignore transient script output" >> scripts\cleanup-result.txt 2>&1
echo. >> scripts\cleanup-result.txt
echo === pushing === >> scripts\cleanup-result.txt
git push origin feat/interactive-softgpu-config >> scripts\cleanup-result.txt 2>&1
echo. >> scripts\cleanup-result.txt
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\cleanup-result.txt
echo DONE >> scripts\cleanup-result.txt
echo wrote scripts\cleanup-result.txt
pause
