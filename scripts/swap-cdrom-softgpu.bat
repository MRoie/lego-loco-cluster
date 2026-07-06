@echo off
echo === info block (find cdrom device id) ===
docker exec win98_rebuild bash -c "(echo 'info block'; sleep 2) | nc -q 3 127.0.0.1 4444"
echo.
echo === ejecting current cdrom ===
docker exec win98_rebuild bash -c "(echo 'eject ide1-cd0'; sleep 2) | nc -q 3 127.0.0.1 4444"
echo.
echo === changing cdrom to softgpu.iso ===
docker exec win98_rebuild bash -c "(echo 'change ide1-cd0 /vm/softgpu.iso'; sleep 2) | nc -q 3 127.0.0.1 4444"
echo.
echo === confirming ===
docker exec win98_rebuild bash -c "(echo 'info block'; sleep 2) | nc -q 3 127.0.0.1 4444"
pause
