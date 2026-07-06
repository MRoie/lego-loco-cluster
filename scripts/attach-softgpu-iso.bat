@echo off
echo Copying softgpu.iso into the running container...
docker cp "%~dp0..\images\softgpu.iso" win98_rebuild:/vm/softgpu.iso
echo.
echo Checking QEMU block device names (info block)...
docker exec win98_rebuild bash -c "(echo 'info block'; sleep 3) | nc -q 3 127.0.0.1 4444"
echo.
pause
