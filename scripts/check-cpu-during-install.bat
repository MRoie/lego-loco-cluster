@echo off
echo === qemu process CPU usage ===
docker exec win98_rebuild bash -c "ps aux | grep -i qemu"
echo === monitor status ===
docker exec win98_rebuild bash -c "(echo 'info status'; sleep 2) | nc -q 3 127.0.0.1 4444"
pause
