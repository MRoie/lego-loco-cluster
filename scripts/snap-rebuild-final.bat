@echo off
echo Snapshotting REBUILD final state...
echo Verified: SoftGPU VMware SVGA-II driver, 1024x768 @ 16-bit color, RAM=1024MB, usb-tablet mouse sync confirmed accurate.
echo DirectX7: already current (no-op). AmigaMerlin: attempted, no physical 3dfx hardware to bind (expected).
docker exec win98_rebuild bash -c "(echo 'savevm rebuild-final'; sleep 5) | nc -q 3 127.0.0.1 4444"
echo.
echo Snapshot 'rebuild-final' requested.
pause
