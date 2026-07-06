@echo off
echo === Host-visible file size (from inside container mount) ===
docker exec win98_rebuild bash -c "ls -la /vm/win98-rebuild.qcow2 && du -h /vm/win98-rebuild.qcow2"
echo.
echo === QEMU block info (actual attached disk) ===
docker exec win98_rebuild bash -c "(echo 'info block'; sleep 2) | nc -q 3 127.0.0.1 4444"
echo.
echo === Flushing QEMU writes to disk (commit) ===
docker exec win98_rebuild bash -c "(echo 'commit all'; sleep 3) | nc -q 3 127.0.0.1 4444"
echo.
echo === Re-checking size after commit ===
docker exec win98_rebuild bash -c "ls -la /vm/win98-rebuild.qcow2"
pause
