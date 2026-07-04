@echo off
cd /d G:\dev\lego-loco-cluster
echo === staging resolved conflicts === > scripts\merge-finish.txt
git add .gitignore containers\qemu-softgpu\entrypoint.sh containers\qemu-softgpu\run-qemu.sh >> scripts\merge-finish.txt 2>&1
echo. >> scripts\merge-finish.txt
echo === remaining unmerged files === >> scripts\merge-finish.txt
git diff --name-only --diff-filter=U >> scripts\merge-finish.txt 2>&1
echo. >> scripts\merge-finish.txt
echo === completing merge commit === >> scripts\merge-finish.txt
git commit --no-edit >> scripts\merge-finish.txt 2>&1
echo. >> scripts\merge-finish.txt
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\merge-finish.txt
echo === log (last 5) === >> scripts\merge-finish.txt
git log --oneline -5 >> scripts\merge-finish.txt 2>&1
echo. >> scripts\merge-finish.txt
echo === final status === >> scripts\merge-finish.txt
git status --short >> scripts\merge-finish.txt 2>&1
echo DONE >> scripts\merge-finish.txt
echo wrote scripts\merge-finish.txt
pause
