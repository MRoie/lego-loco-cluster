@echo off
echo Snapshotting REBUILD baseline (working Win98+Loco desktop, pre-SoftGPU)...
docker exec win98_rebuild bash -c "(echo 'savevm rebuild-baseline-with-loco'; sleep 3) | nc -q 3 127.0.0.1 4444"
echo.
pause
