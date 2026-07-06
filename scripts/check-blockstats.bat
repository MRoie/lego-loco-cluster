@echo off
echo === container status ===
docker ps -f name=win98_rebuild
echo.
echo === qemu process ===
docker exec win98_rebuild bash -c "ps aux | grep -i qemu | grep -v grep"
echo.
echo === block device I/O stats (run twice manually to compare) ===
docker exec win98_rebuild bash -c "(echo 'info blockstats'; sleep 2) | nc -q 3 127.0.0.1 4444"
pause
