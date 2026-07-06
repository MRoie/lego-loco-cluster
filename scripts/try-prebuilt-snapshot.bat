@echo off
echo === Trying to pull ghcr.io/mroie/qemu-snapshots:win98-base ===
docker pull ghcr.io/mroie/qemu-snapshots:win98-base
echo.
echo === If that failed, list what tags/repos actually exist under mroie (best effort) ===
echo === Inspecting image contents (if pull succeeded) ===
docker run --rm --entrypoint sh ghcr.io/mroie/qemu-snapshots:win98-base -c "find / -maxdepth 4 -iname '*.qcow2' 2>/dev/null; echo DONE" 2>&1
pause
