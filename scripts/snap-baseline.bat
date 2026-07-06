@echo off
REM Saves a live QEMU snapshot named 'baseline-before-drivers'.
docker exec win98_interactive_softgpu bash -c "(echo 'savevm baseline-before-drivers'; sleep 3) | nc -q 3 127.0.0.1 4444"
echo.
echo Snapshot 'baseline-before-drivers' requested.
pause
