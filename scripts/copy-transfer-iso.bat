@echo off
setlocal
set REPO=%~dp0..
set IMG=%REPO%\images
echo Copying transfer.iso into running container via docker cp...
docker cp "%IMG%\transfer.iso" win98_rebuild:/vm/transfer.iso
echo.
echo === Verifying ===
docker exec win98_rebuild bash -c "ls -la /vm/transfer.iso"
pause
