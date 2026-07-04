@echo off
set IMAGES_DIR=%~dp0..\images
echo Backing up current (possibly corrupted) win98.qcow2 as win98-corrupted.qcow2.bak ...
copy /Y "%IMAGES_DIR%\win98.qcow2" "%IMAGES_DIR%\win98-corrupted.qcow2.bak"
echo.
echo Restoring win98-pre-restart.qcow2.bak over win98.qcow2 ...
copy /Y "%IMAGES_DIR%\win98-pre-restart.qcow2.bak" "%IMAGES_DIR%\win98.qcow2"
echo.
echo === Done. Files: ===
dir "%IMAGES_DIR%\*.qcow2*"
pause
