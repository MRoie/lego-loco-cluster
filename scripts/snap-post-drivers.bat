@echo off
REM Saves a live QEMU snapshot named 'post-softgpu-drivers'.
REM Run this after the SoftGPU driver install + reboot has settled.
docker exec win98_interactive_softgpu bash -c "(echo 'savevm post-softgpu-drivers'; sleep 3) | nc -q 3 127.0.0.1 4444"
echo.
echo Snapshot 'post-softgpu-drivers' requested.
pause
