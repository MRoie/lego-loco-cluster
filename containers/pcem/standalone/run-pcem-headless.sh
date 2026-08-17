#!/bin/bash
# Boot the safe512 Win98 disk (raw, converted from the QEMU golden image) under
# PCem v17 with a Socket7/430VX board + Voodoo3 3000, rendered into a headless
# Xvfb and bridged to VNC by x11vnc.
set -eux

pkill -f "Xvfb :99" 2>/dev/null || true
rm -f /tmp/.X99-lock 2>/dev/null || true
Xvfb :99 -screen 0 1024x768x24 -ac +extension GLX +render -noreset >/work/xvfb.log 2>&1 &
sleep 3
export DISPLAY=:99
export LIBGL_ALWAYS_SOFTWARE=1

pkill -f x11vnc 2>/dev/null || true
x11vnc -display :99 -forever -shared -rfbport 5901 -nopw -listen 0.0.0.0 -bg >/work/x11vnc.log 2>&1
sleep 2

export HOME=/work
mkdir -p /work/.pcem
rm -rf /work/.pcem/roms
ln -sfn /work/roms /work/.pcem/roms

cd /work
exec ./pcem --config /work/pcem.cfg >/work/pcem.log 2>&1
