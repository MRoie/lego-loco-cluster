#!/bin/bash
# Boot the SoftGPU golden image (netready.qcow2) with the freshly built
# qemu-3dfx (Mesa/Glide passthrough), rendered into a headless Xvfb via
# software Mesa (llvmpipe) and bridged to VNC :5901 by x11vnc.
set -eux
QEMU=/work/opt/qemu-3dfx/bin/qemu-system-i386

# --- headless X display for the SDL/OpenGL context ---
pkill -f "Xvfb :99" 2>/dev/null || true
rm -f /tmp/.X99-lock 2>/dev/null || true
Xvfb :99 -screen 0 1024x768x24 -ac +extension GLX +render -noreset >/work/xvfb.log 2>&1 &
sleep 3
export DISPLAY=:99
# force software Mesa (no GPU in the container)
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe
export SDL_VIDEODRIVER=x11
export SDL_VIDEO_WINDOW_POS=0,0
export SDL_VIDEO_CENTERED=0

# sanity: does GLX work in Xvfb?
glxinfo -B 2>/dev/null | head -8 || echo "glxinfo unavailable"

# --- bridge the X screen to VNC 5901 ---
pkill -f x11vnc 2>/dev/null || true
x11vnc -display :99 -forever -shared -rfbport 5901 -nopw -listen 0.0.0.0 -bg >/work/x11vnc.log 2>&1
sleep 2

# --- launch qemu-3dfx with SDL/OpenGL passthrough display ---
exec "$QEMU" \
  -accel tcg,tb-size=1024 \
  -M pc -cpu qemu32,+sse3,+ssse3,+sse4.1 -m 512 -smp 1 -snapshot \
  -hda /img/qemu-softgpu/tmp-bake/netready.qcow2 \
  -device sb16,audiodev=snd0 -audiodev none,id=snd0 \
  -vga vmware -usb -device usb-tablet \
  -display sdl,gl=on -full-screen \
  -rtc base=localtime \
  -netdev user,id=n0 -device ne2k_pci,netdev=n0 \
  >/work/qemu.log 2>&1
