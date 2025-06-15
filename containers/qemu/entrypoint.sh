#!/usr/bin/env bash
set -euo pipefail

BRIDGE=${BRIDGE:-loco-br}
TAP_IF=${TAP_IF:-tap0}
DISK=${DISK:-/images/win98.qcow2}


# Start virtual display
export DISPLAY=:99
Xvfb :99 -screen 0 1024x768x24 &
XVFB_PID=$!

# Start PulseAudio daemon
pulseaudio --start --exit-idle-time=-1
echo "🔈 PulseAudio started"

# Check if TAP interface exists (it should be created by the host setup script)
if ! ip link show "$TAP_IF" &>/dev/null; then
  echo "❌ TAP interface $TAP_IF not found. Make sure to run setup_bridge.sh on the host first." >&2
  exit 1
fi

echo "🌐 Using existing TAP interface $TAP_IF"

qemu-system-i386 \
  -M pc -cpu pentium2 \
  -m 512 -hda "$DISK" \
  -net nic,model=ne2k_pci -net tap,ifname=$TAP_IF,script=no,downscript=no \
  -device sb16,audiodev=snd0 \
  -vga cirrus -display vnc=:1 \
  -audiodev pa,id=snd0 \
  -rtc base=localtime &
EMU_PID=$!

# Wait for QEMU to start
sleep 5
echo "🖥️  QEMU started with VNC display on :5901"

# Start GStreamer pipeline for screen capture and streaming
echo "📹 Starting simple video stream..."
gst-launch-1.0 -v \
  ximagesrc display-name=:99 use-damage=0 ! \
  videoconvert ! \
  videoscale ! \
  video/x-raw,width=640,height=480 ! \
  x264enc tune=zerolatency bitrate=500 speed-preset=ultrafast ! \
  rtph264pay ! \
  udpsink host=127.0.0.1 port=5000 &
GSTREAMER_PID=$!

# Cleanup function
cleanup() {
  echo "🧹 Cleaning up..."
  kill $EMU_PID $XVFB_PID $GSTREAMER_PID 2>/dev/null || true
  exit 0
}

trap cleanup SIGTERM SIGINT

wait $EMU_PID
