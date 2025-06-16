#!/usr/bin/env bash
set -euo pipefail

BRIDGE=${BRIDGE:-loco-br}
TAP_IF=${TAP_IF:-tap0}
DISK=${DISK:-/images/win98.qcow2}


# Start virtual display
echo "🖥️  Starting virtual display..."
# Find an available display number
for display_num in {99..199}; do
  if ! pgrep -f "Xvfb :$display_num" > /dev/null && ! netstat -ln | grep -q ":60$((display_num))"; then
    DISPLAY_NUM=$display_num
    break
  fi
done

# Kill any existing processes on this display
pkill -f "Xvfb :$DISPLAY_NUM" 2>/dev/null || true
sleep 1

export DISPLAY=:$DISPLAY_NUM
Xvfb :$DISPLAY_NUM -screen 0 1024x768x24 &
XVFB_PID=$!
sleep 3

# Verify Xvfb started successfully
if ! kill -0 $XVFB_PID 2>/dev/null; then
  echo "❌ Failed to start Xvfb on display :$DISPLAY_NUM" >&2
  exit 1
fi
echo "✅ Xvfb started on display :$DISPLAY_NUM"

# Start PulseAudio daemon
pulseaudio --start --exit-idle-time=-1
echo "🔈 PulseAudio started"

# Create isolated TAP bridge inside this container
echo "🌐 Setting up isolated TAP bridge..."
ip link add name "$BRIDGE" type bridge
ip addr add 192.168.10.1/24 dev "$BRIDGE"
ip link set "$BRIDGE" up

# Create TAP interface
ip tuntap add "$TAP_IF" mode tap
ip link set "$TAP_IF" master "$BRIDGE"
ip link set "$TAP_IF" up

echo "✅ Created isolated TAP bridge $BRIDGE with interface $TAP_IF"

# Create a unique snapshot for this instance to avoid file locking issues
SNAPSHOT_NAME="/tmp/win98_$(date +%s)_$$.qcow2"
echo "📀 Creating snapshot: $SNAPSHOT_NAME"
qemu-img create -f qcow2 -b "$DISK" "$SNAPSHOT_NAME"

echo "🚀 Starting QEMU..."
qemu-system-i386 \
  -M pc -cpu pentium2 \
  -m 512 -hda "$SNAPSHOT_NAME" \
  -net nic,model=ne2k_pci -net tap,ifname=$TAP_IF,script=no,downscript=no \
  -device sb16,audiodev=snd0 \
  -vga cirrus -display vnc=:1 \
  -audiodev pa,id=snd0 \
  -rtc base=localtime \
  -boot menu=on,splash-time=5000 \
  -no-shutdown \
  -no-reboot \
  -monitor none &

EMU_PID=$!

# Wait a bit longer for QEMU to initialize
sleep 8
if ! kill -0 $EMU_PID 2>/dev/null; then
  echo "❌ QEMU process died" >&2
  wait $EMU_PID
  exit 1
fi

echo "✅ QEMU started successfully (PID: $EMU_PID)"

# Wait for QEMU to start
sleep 5
echo "🖥️  QEMU started with VNC display on :5901"

# Start GStreamer pipeline for screen capture and streaming
echo "📹 Starting simple video stream..."
gst-launch-1.0 -v \
  ximagesrc display-name=:$DISPLAY_NUM use-damage=0 ! \
  videoconvert ! \
  videoscale ! \
  video/x-raw,width=640,height=480 ! \
  x264enc tune=zerolatency bitrate=500 speed-preset=ultrafast ! \
  rtph264pay ! \
  udpsink host=127.0.0.1 port=5000 &
GSTREAMER_PID=$!

echo "✅ Container setup complete!"
echo "   VNC: localhost:5901"
echo "   Video stream: UDP port 5000"
echo "   QEMU PID: $EMU_PID"
echo "   GStreamer PID: $GSTREAMER_PID"

# Cleanup function
cleanup() {
  echo "🧹 Cleaning up..."
  kill $EMU_PID $XVFB_PID $GSTREAMER_PID 2>/dev/null || true
  rm -f "$SNAPSHOT_NAME" 2>/dev/null || true
  exit 0
}

trap cleanup SIGTERM SIGINT

wait $EMU_PID
