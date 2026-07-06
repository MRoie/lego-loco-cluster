@echo off
cd /d G:\dev\lego-loco-cluster
echo === git status --short === > scripts\merge-status.txt
git status --short >> scripts\merge-status.txt
echo. >> scripts\merge-status.txt
echo === git diff --name-only --diff-filter=U (unmerged) === >> scripts\merge-status.txt
git diff --name-only --diff-filter=U >> scripts\merge-status.txt
echo. >> scripts\merge-status.txt
echo DONE >> scripts\merge-status.txt
echo wrote scripts\merge-status.txt
pause
