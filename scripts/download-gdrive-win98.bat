@echo off
set SCRIPTS_DIR=%~dp0
set IMAGES_DIR=%~dp0..\images
if not exist "%IMAGES_DIR%" mkdir "%IMAGES_DIR%"
echo Downloading win98-gdrive.qcow2 via throwaway Alpine container...
docker run --rm -v "%SCRIPTS_DIR%:/work" -v "%IMAGES_DIR%:/out" alpine:latest sh /work/gdrive-download-inner.sh
echo.
echo === Result ===
dir "%IMAGES_DIR%\win98-gdrive.qcow2"
pause
