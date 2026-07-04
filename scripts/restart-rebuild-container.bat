@echo off
echo Restarting win98_rebuild container (qemu was hung at boot ROM after ACPI restart)...
echo Using 'docker restart' (not stop+start) since container has --rm, to avoid losing it.
docker restart win98_rebuild
echo.
echo Waiting a few seconds...
timeout /t 5 /nobreak >nul
docker ps -f name=win98_rebuild
pause
