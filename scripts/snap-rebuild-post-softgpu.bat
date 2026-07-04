@echo off
echo Snapshotting REBUILD post-SoftGPU driver install (VMware SVGA-II driver confirmed working, 1024x768, 16-bit)...
docker exec win98_rebuild bash -c "(echo 'savevm rebuild-post-softgpu-drivers'; sleep 5) | nc -q 3 127.0.0.1 4444"
echo.
echo Snapshot 'rebuild-post-softgpu-drivers' requested.
pause
