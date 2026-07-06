@echo off
echo === container status ===
docker ps -a -f name=win98_interactive_softgpu
echo === qemu process ===
docker exec win98_interactive_softgpu bash -c "ps aux | grep -i qemu"
echo === last 30 lines of container logs ===
docker logs --tail 30 win98_interactive_softgpu
pause
