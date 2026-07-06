@echo off
echo === qemu process ===
docker exec win98_rebuild bash -c "ps aux | grep -i qemu"
echo === monitor status ===
docker exec win98_rebuild bash -c "(echo 'info status'; sleep 2) | nc -q 3 127.0.0.1 4444"
echo === last 40 lines of container logs ===
docker logs --tail 40 win98_rebuild
pause
