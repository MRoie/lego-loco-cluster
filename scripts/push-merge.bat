@echo off
cd /d G:\dev\lego-loco-cluster
echo === removing transient debug output files === > scripts\push-result.txt
del /f /q scripts\merge-status.txt scripts\merge-finish.txt >> scripts\push-result.txt 2>&1
echo. >> scripts\push-result.txt
echo === staging remaining helper scripts === >> scripts\push-result.txt
git add scripts\check-conflicts.bat scripts\finish-merge.bat scripts\push-merge.bat >> scripts\push-result.txt 2>&1
git status --short >> scripts\push-result.txt 2>&1
echo. >> scripts\push-result.txt
echo === committing helper scripts === >> scripts\push-result.txt
git commit -m "Add merge-conflict-check and finish-merge helper scripts" >> scripts\push-result.txt 2>&1
echo. >> scripts\push-result.txt
echo === pushing to origin === >> scripts\push-result.txt
git push origin feat/interactive-softgpu-config >> scripts\push-result.txt 2>&1
echo. >> scripts\push-result.txt
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\push-result.txt
git log --oneline -3 >> scripts\push-result.txt 2>&1
echo DONE >> scripts\push-result.txt
echo wrote scripts\push-result.txt
pause
