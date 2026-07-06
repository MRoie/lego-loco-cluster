@echo off
echo Sending Ctrl-Alt-Delete via QEMU monitor sendkey...
docker exec win98_rebuild bash -c "(echo 'sendkey ctrl-alt-delete'; sleep 2) | nc -q 3 127.0.0.1 4444"
pause
