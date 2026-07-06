@echo off
echo Snapshotting REBUILD post-DirectX7 + AmigaMerlin attempt...
echo (DirectX7: no-op, newer version already present via SoftGPU base image)
echo (AmigaMerlin: Setup.exe ran, copied files, errored on PnP binding - expected, no physical 3dfx Voodoo hardware present in this VM)
docker exec win98_rebuild bash -c "(echo 'savevm rebuild-post-directx-amigamerlin'; sleep 5) | nc -q 3 127.0.0.1 4444"
echo.
echo Snapshot 'rebuild-post-directx-amigamerlin' requested.
pause
