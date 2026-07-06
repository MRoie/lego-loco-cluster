@echo off
set IMAGES_DIR=%~dp0..\images
set OLD_TAG=3dca1f1fd98a86528c2140ae3d484e959244ed5b
echo Pulling oldest known win98-softgpu tag: %OLD_TAG% (published ~1 year ago)...
docker pull ghcr.io/mroie/lego-loco-cluster/win98-softgpu:%OLD_TAG%
echo.
echo Extracting win98.qcow2.builtin from that older image to win98-old-tag.qcow2 ...
docker run --rm --entrypoint cp -v "%IMAGES_DIR%:/out" ghcr.io/mroie/lego-loco-cluster/win98-softgpu:%OLD_TAG% /opt/builtin-images/win98.qcow2.builtin /out/win98-old-tag.qcow2
echo.
echo === Result ===
dir "%IMAGES_DIR%\win98-old-tag.qcow2"
pause
