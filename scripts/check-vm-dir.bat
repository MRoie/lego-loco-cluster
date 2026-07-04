@echo off
echo === ls -la /vm inside container ===
docker exec win98_rebuild bash -c "ls -la /vm/"
pause
