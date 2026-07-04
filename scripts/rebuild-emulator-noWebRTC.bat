@echo off
cd /d G:\dev\lego-loco-cluster
powershell -ExecutionPolicy Bypass -File "scripts\rebuild-emulator-noWebRTC.ps1" > scripts\rebuild-emulator-noWebRTC-result.txt 2>&1
echo === EXIT CODE: %ERRORLEVEL% === >> scripts\rebuild-emulator-noWebRTC-result.txt
echo DONE >> scripts\rebuild-emulator-noWebRTC-result.txt
echo wrote scripts\rebuild-emulator-noWebRTC-result.txt
