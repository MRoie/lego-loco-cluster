@echo off
REM Saves a live QEMU snapshot named 'resolution-1024x768-ready'.
REM Run this after the guest display resolution has been changed to 1024x768.
docker exec win98_interactive_softgpu bash -c "(echo 'savevm resolution-1024x768-ready'; sleep 3) | nc -q 3 127.0.0.1 4444"
echo.
echo Snapshot 'resolution-1024x768-ready' requested.
pause
