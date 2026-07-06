@echo off
echo === Host-side softgpu.iso size ===
dir "%~dp0..\images\softgpu.iso"
echo.
echo === Container-side /vm/softgpu.iso size ===
docker exec win98_rebuild bash -c "ls -la /vm/softgpu.iso && md5sum /vm/softgpu.iso"
echo.
echo === Host-side md5 (may take a bit) ===
certutil -hashfile "%~dp0..\images\softgpu.iso" MD5
pause
