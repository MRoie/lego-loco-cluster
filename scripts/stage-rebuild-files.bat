@echo off
setlocal
set REPO=%~dp0..
set CONT=%REPO%\containers
set IMG=%REPO%\images
if not exist "%IMG%" mkdir "%IMG%"

echo Copying win98_loco_qemu.qcow2 -^> images\win98-rebuild.qcow2 ...
copy /Y "%CONT%\win98_loco_qemu.qcow2" "%IMG%\win98-rebuild.qcow2"

echo Copying Windows 98 Second Edition.iso -^> images\win98se.iso ...
copy /Y "%CONT%\Windows 98 Second Edition.iso" "%IMG%\win98se.iso"

echo.
echo === Result ===
dir "%IMG%\win98-rebuild.qcow2" "%IMG%\win98se.iso"
echo DONE_MARKER
pause
