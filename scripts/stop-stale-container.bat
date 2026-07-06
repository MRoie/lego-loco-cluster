@echo off
echo Stopping stale container (built before -monitor flag was added)...
docker stop win98_interactive_softgpu
echo.
echo Container stopped/removed. Verifying...
docker ps -a -f name=win98_interactive_softgpu
echo.
echo Done - now re-run win98-softgpu-autorun.bat to build fresh with the monitor port.
pause
