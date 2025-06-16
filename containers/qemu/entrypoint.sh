#!/usr/bin/env bash
set -euo pipefail

BRIDGE=${BRIDGE:-loco-br}
TAP_IF=${TAP_IF:-tap0}
DISK=${DISK:-/images/win98.qcow2}
SNAPSHOT_REGISTRY=${SNAPSHOT_REGISTRY:-ghcr.io/mroie/qemu-snapshots}
SNAPSHOT_TAG=${SNAPSHOT_TAG:-win98-base}
USE_PREBUILT_SNAPSHOT=${USE_PREBUILT_SNAPSHOT:-true}


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

# Clean up any existing interfaces first
ip link delete "$TAP_IF" 2>/dev/null || true
ip link delete "$BRIDGE" 2>/dev/null || true

# Create bridge
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

# Pre-built snapshot strategy
if [ "$USE_PREBUILT_SNAPSHOT" = "true" ]; then
  echo "📥 Attempting to download pre-built snapshot..."
  SNAPSHOT_URL="${SNAPSHOT_REGISTRY}:${SNAPSHOT_TAG}"
  
  # Try to download pre-built snapshot using skopeo/crane
  if command -v skopeo >/dev/null 2>&1; then
    echo "   Using skopeo to download snapshot from: $SNAPSHOT_URL"
    if skopeo copy "docker://${SNAPSHOT_URL}" "oci-archive:${SNAPSHOT_NAME}.tar" 2>/dev/null; then
      # Extract the actual qcow2 file from the OCI archive
      if tar -xf "${SNAPSHOT_NAME}.tar" -C /tmp/ --wildcards "*/layer.tar" 2>/dev/null; then
        # Find and extract the qcow2 from the layer
        LAYER_TAR=$(find /tmp -name "layer.tar" | head -1)
        if [ -n "$LAYER_TAR" ] && tar -tf "$LAYER_TAR" | grep -q "\.qcow2$"; then
          tar -xf "$LAYER_TAR" -C /tmp/ --wildcards "*.qcow2"
          EXTRACTED_QCOW2=$(find /tmp -name "*.qcow2" -not -path "*/tmp/win98_*" | head -1)
          if [ -n "$EXTRACTED_QCOW2" ]; then
            cp "$EXTRACTED_QCOW2" "$SNAPSHOT_NAME"
            echo "✅ Successfully downloaded and extracted pre-built snapshot"
            rm -f "${SNAPSHOT_NAME}.tar" "$LAYER_TAR" "$EXTRACTED_QCOW2"
            SKIP_SNAPSHOT_CREATION=true
          fi
        fi
      fi
    fi
  elif command -v crane >/dev/null 2>&1; then
    echo "   Using crane to download snapshot from: $SNAPSHOT_URL"
    if crane export "$SNAPSHOT_URL" - | tar -x -C /tmp/ --wildcards "*.qcow2" 2>/dev/null; then
      EXTRACTED_QCOW2=$(find /tmp -name "*.qcow2" -not -path "*/tmp/win98_*" | head -1)
      if [ -n "$EXTRACTED_QCOW2" ]; then
        cp "$EXTRACTED_QCOW2" "$SNAPSHOT_NAME"
        echo "✅ Successfully downloaded and extracted pre-built snapshot"
        rm -f "$EXTRACTED_QCOW2"
        SKIP_SNAPSHOT_CREATION=true
      fi
    fi
  else
    echo "   No container registry tools (skopeo/crane) available, falling back to base image"
  fi
  
  if [ "$SKIP_SNAPSHOT_CREATION" != "true" ]; then
    echo "   Failed to download pre-built snapshot, falling back to creating from base image"
  fi
fi

if [ "$SKIP_SNAPSHOT_CREATION" != "true" ]; then
  echo "📀 Creating snapshot from base image: $SNAPSHOT_NAME"
  
  # Check if the base disk image exists
  if [ ! -f "$DISK" ]; then
    echo "❌ Base disk image not found: $DISK" >&2
    echo "   Available files in /images:" >&2
    ls -la /images/ 2>/dev/null || echo "   /images directory not accessible" >&2
    exit 1
  fi
  
  qemu-img create -f qcow2 -b "$DISK" "$SNAPSHOT_NAME"
  if [ $? -ne 0 ]; then
    echo "❌ Failed to create snapshot" >&2
    exit 1
  fi
else
  echo "📀 Using pre-built snapshot: $SNAPSHOT_NAME"
fi
  exit 1
fi

echo "✅ Base disk image found: $DISK"
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
