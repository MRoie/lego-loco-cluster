@echo off
echo Sending ESC via QEMU monitor sendkey (bypasses VNC input path)...
docker exec win98_rebuild bash -c "(echo 'sendkey esc'; sleep 2; echo 'info status'; sleep 2) | nc -q 3 127.0.0.1 4444"
pause
