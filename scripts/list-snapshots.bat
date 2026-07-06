@echo off
REM Lists live QEMU snapshots saved inside the running win98_interactive_softgpu container.
docker exec win98_interactive_softgpu bash -c "(sleep 1; echo 'info snapshots'; sleep 3) | nc -q 3 127.0.0.1 4444"
echo.
pause
