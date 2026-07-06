@echo off
echo Swapping CD-ROM to softgpu.iso (live, no restart)...
docker exec win98_rebuild bash -c "(echo 'change ide1-cd0 /vm/softgpu.iso'; sleep 3; echo 'info block'; sleep 2) | nc -q 3 127.0.0.1 4444"
echo.
pause
