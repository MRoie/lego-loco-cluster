@echo off
echo Stopping old win98_interactive_softgpu container (corrupted-disk based), freeing ports 5900/6080...
docker stop win98_interactive_softgpu 2>nul
docker rm -f win98_interactive_softgpu 2>nul
echo Done.
docker ps -a --filter "name=win98"
pause
