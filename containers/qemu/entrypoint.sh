#!/usr/bin/env bash
set -euo pipefail

# Enhanced logging function
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log_error() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ❌ ERROR: $1" >&2
}

log_success() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ✅ SUCCESS: $1"
}

log_info() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ℹ️  INFO: $1"
}

# Configuration with defaults
BRIDGE=${BRIDGE:-loco-br}
TAP_IF=${TAP_IF:-tap0}
DISK=${DISK:-/images/win98.qcow2}
SNAPSHOT_REGISTRY=${SNAPSHOT_REGISTRY:-ghcr.io/mroie/qemu-snapshots}
SNAPSHOT_TAG=${SNAPSHOT_TAG:-win98-base}
USE_PREBUILT_SNAPSHOT=${USE_PREBUILT_SNAPSHOT:-true}

log_info "Starting QEMU emulator container with configuration:"
log_info "  BRIDGE=$BRIDGE"
log_info "  TAP_IF=$TAP_IF"
log_info "  DISK=$DISK"
log_info "  USE_PREBUILT_SNAPSHOT=$USE_PREBUILT_SNAPSHOT"
log_info "  SNAPSHOT_REGISTRY=$SNAPSHOT_REGISTRY"
log_info "  SNAPSHOT_TAG=$SNAPSHOT_TAG"

# === STEP 1: Virtual Display Setup ===
log_info "Setting up virtual display..."

# Use provided DISPLAY_NUM or find an available display number
if [ -n "${DISPLAY_NUM:-}" ]; then
  log_info "Using provided display number: $DISPLAY_NUM"
else
  log_info "No DISPLAY_NUM provided, auto-detecting..."
  DISPLAY_NUM=""
  for display_num in {99..199}; do
    if ! pgrep -f "Xvfb :$display_num" > /dev/null && ! netstat -ln | grep -q ":60$((display_num))" 2>/dev/null; then
      DISPLAY_NUM=$display_num
      break
    fi
  done

  if [ -z "$DISPLAY_NUM" ]; then
    log_error "No available display numbers found"
    exit 1
  fi
  log_info "Auto-detected display number: $DISPLAY_NUM"
fi

# Kill any existing processes on this display and clean up lock files
if pgrep -f "Xvfb :$DISPLAY_NUM" > /dev/null; then
  log_info "Killing existing Xvfb on display :$DISPLAY_NUM"
  pkill -f "Xvfb :$DISPLAY_NUM" || true
  sleep 2
fi

# Remove any leftover X server lock files
if [ -f "/tmp/.X${DISPLAY_NUM}-lock" ]; then
  log_info "Removing leftover X server lock file"
  rm -f "/tmp/.X${DISPLAY_NUM}-lock" || true
fi

# Start Xvfb
export DISPLAY=:$DISPLAY_NUM
log_info "Starting Xvfb on display :$DISPLAY_NUM"
Xvfb :$DISPLAY_NUM -screen 0 1024x768x24 &
XVFB_PID=$!
sleep 3

# Verify Xvfb started successfully
if ! kill -0 $XVFB_PID 2>/dev/null; then
  log_error "Failed to start Xvfb on display :$DISPLAY_NUM"
  exit 1
fi
log_success "Xvfb started on display :$DISPLAY_NUM (PID: $XVFB_PID)"

# === STEP 2: Audio Setup ===
log_info "Starting PulseAudio daemon..."
if pulseaudio --start --exit-idle-time=-1; then
  log_success "PulseAudio started successfully"
else
  log_error "Failed to start PulseAudio, continuing without audio"
fi

# === STEP 3: Network Setup ===
log_info "Setting up isolated TAP bridge..."

# Clean up any existing interfaces first
log_info "Cleaning up existing network interfaces..."
if ip link show "$TAP_IF" &>/dev/null; then
  log_info "Removing existing TAP interface: $TAP_IF"
  ip link delete "$TAP_IF" || true
fi

if ip link show "$BRIDGE" &>/dev/null; then
  log_info "Removing existing bridge: $BRIDGE"
  ip link delete "$BRIDGE" || true
fi

# Create bridge
log_info "Creating bridge: $BRIDGE"
if ip link add name "$BRIDGE" type bridge; then
  log_success "Bridge $BRIDGE created"
else
  log_error "Failed to create bridge $BRIDGE"
  exit 1
fi

if ip addr add 192.168.10.1/24 dev "$BRIDGE"; then
  log_success "IP address assigned to bridge $BRIDGE"
else
  log_error "Failed to assign IP to bridge $BRIDGE"
  exit 1
fi

if ip link set "$BRIDGE" up; then
  log_success "Bridge $BRIDGE is up"
else
  log_error "Failed to bring up bridge $BRIDGE"
  exit 1
fi

# Create TAP interface
log_info "Creating TAP interface: $TAP_IF"
if ip tuntap add "$TAP_IF" mode tap; then
  log_success "TAP interface $TAP_IF created"
else
  log_error "Failed to create TAP interface $TAP_IF"
  exit 1
fi

if ip link set "$TAP_IF" master "$BRIDGE"; then
  log_success "TAP interface $TAP_IF added to bridge $BRIDGE"
else
  log_error "Failed to add TAP interface to bridge"
  exit 1
fi

if ip link set "$TAP_IF" up; then
  log_success "TAP interface $TAP_IF is up"
else
  log_error "Failed to bring up TAP interface $TAP_IF"
  exit 1
fi

log_success "Network setup complete - Bridge: $BRIDGE, TAP: $TAP_IF"

# === STEP 4: Disk Image Setup ===
# Create a unique snapshot for this instance to avoid file locking issues
SNAPSHOT_NAME="/tmp/win98_$(date +%s)_$$.qcow2"
SKIP_SNAPSHOT_CREATION=false

log_info "Preparing disk image: $SNAPSHOT_NAME"

# Pre-built snapshot strategy
if [ "$USE_PREBUILT_SNAPSHOT" = "true" ]; then
  log_info "Attempting to download pre-built snapshot..."
  SNAPSHOT_URL="${SNAPSHOT_REGISTRY}:${SNAPSHOT_TAG}"
  log_info "Snapshot URL: $SNAPSHOT_URL"
  
  # Try to download pre-built snapshot using skopeo/crane
  if command -v skopeo >/dev/null 2>&1; then
    log_info "Using skopeo to download snapshot"
    if skopeo copy "docker://${SNAPSHOT_URL}" "oci-archive:${SNAPSHOT_NAME}.tar" 2>/dev/null; then
      log_info "Successfully downloaded snapshot archive"
      # Extract the actual qcow2 file from the OCI archive
      if tar -xf "${SNAPSHOT_NAME}.tar" -C /tmp/ --wildcards "*/layer.tar" 2>/dev/null; then
        # Find and extract the qcow2 from the layer
        LAYER_TAR=$(find /tmp -name "layer.tar" | head -1)
        if [ -n "$LAYER_TAR" ] && tar -tf "$LAYER_TAR" | grep -q "\.qcow2$"; then
          tar -xf "$LAYER_TAR" -C /tmp/ --wildcards "*.qcow2"
          EXTRACTED_QCOW2=$(find /tmp -name "*.qcow2" -not -path "*/tmp/win98_*" | head -1)
          if [ -n "$EXTRACTED_QCOW2" ]; then
            cp "$EXTRACTED_QCOW2" "$SNAPSHOT_NAME"
            log_success "Successfully downloaded and extracted pre-built snapshot"
            rm -f "${SNAPSHOT_NAME}.tar" "$LAYER_TAR" "$EXTRACTED_QCOW2"
            SKIP_SNAPSHOT_CREATION=true
          fi
        fi
      fi
    else
      log_error "Failed to download snapshot with skopeo"
    fi
  elif command -v crane >/dev/null 2>&1; then
    log_info "Using crane to download snapshot"
    if crane export "$SNAPSHOT_URL" - | tar -x -C /tmp/ --wildcards "*.qcow2" 2>/dev/null; then
      EXTRACTED_QCOW2=$(find /tmp -name "*.qcow2" -not -path "*/tmp/win98_*" | head -1)
      if [ -n "$EXTRACTED_QCOW2" ]; then
        cp "$EXTRACTED_QCOW2" "$SNAPSHOT_NAME"
        log_success "Successfully downloaded and extracted pre-built snapshot"
        rm -f "$EXTRACTED_QCOW2"
        SKIP_SNAPSHOT_CREATION=true
      fi
    else
      log_error "Failed to download snapshot with crane"
    fi
  else
    log_info "No container registry tools (skopeo/crane) available, falling back to base image"
  fi
  
  if [ "$SKIP_SNAPSHOT_CREATION" != "true" ]; then
    log_info "Failed to download pre-built snapshot, falling back to creating from base image"
  fi
fi

if [ "$SKIP_SNAPSHOT_CREATION" != "true" ]; then
  log_info "Creating snapshot from base image: $DISK"
  
  # Check if the base disk image exists
  if [ ! -f "$DISK" ]; then
    log_error "Base disk image not found: $DISK"
    log_info "Available files in /images:"
    ls -la /images/ 2>/dev/null || log_error "/images directory not accessible"
    log_info "Available files in /tmp:"
    ls -la /tmp/ 2>/dev/null || log_error "/tmp directory not accessible"
    exit 1
  fi
  
  log_success "Base disk image found: $DISK"
  log_info "File details: $(ls -lh "$DISK")"
  
  log_info "Creating QCOW2 snapshot: $SNAPSHOT_NAME"
  if qemu-img create -f qcow2 -b "$DISK" -F qcow2 "$SNAPSHOT_NAME"; then
    log_success "Snapshot created successfully"
    log_info "Snapshot details: $(ls -lh "$SNAPSHOT_NAME")"
  else
    log_error "Failed to create snapshot"
    exit 1
  fi
else
  log_success "Using pre-built snapshot: $SNAPSHOT_NAME"
  log_info "Snapshot details: $(ls -lh "$SNAPSHOT_NAME")"
fi

# === STEP 5: QEMU Startup ===
log_info "Starting QEMU emulator..."
log_info "QEMU command: qemu-system-i386 -M pc -cpu pentium2 -m 512 -hda $SNAPSHOT_NAME ..."

# Add debugging to see what we're actually booting from
log_info "Checking disk image contents..."
qemu-img info "$SNAPSHOT_NAME" | while read line; do log_info "  $line"; done

qemu-system-i386 \
  -M pc -cpu pentium2 \
  -m 512 -hda "$SNAPSHOT_NAME" \
  -net nic,model=ne2k_pci -net tap,ifname=$TAP_IF,script=no,downscript=no \
  -device sb16,audiodev=snd0 \
  -vga std -display vnc=0.0.0.0:1 \
  -audiodev pa,id=snd0 \
  -rtc base=localtime \
  -boot order=dc,menu=on,splash-time=5000 \
  -no-shutdown \
  -no-reboot \
  -monitor none &

EMU_PID=$!
log_info "QEMU started with PID: $EMU_PID"

# Wait for QEMU to initialize
log_info "Waiting for QEMU to initialize..."
sleep 30

if ! kill -0 $EMU_PID 2>/dev/null; then
  log_error "QEMU process died during startup"
  wait $EMU_PID
  exit 1
fi

log_success "QEMU started successfully (PID: $EMU_PID)"
log_info "VNC display available on :5901"

# === STEP 6: Video Streaming Setup ===
log_info "Starting GStreamer video stream..."
gst-launch-1.0 -v \
  ximagesrc display-name=:$DISPLAY_NUM use-damage=0 ! \
  queue max-size-time=100000000 max-size-buffers=5 leaky=downstream ! \
  videoconvert ! \
  queue max-size-time=100000000 max-size-buffers=5 leaky=downstream ! \
  videoscale ! \
  video/x-raw,width=640,height=480,framerate=25/1 ! \
  queue max-size-time=100000000 max-size-buffers=5 leaky=downstream ! \
  x264enc tune=zerolatency bitrate=500 speed-preset=ultrafast key-int-max=25 ! \
  queue max-size-time=100000000 max-size-buffers=5 leaky=downstream ! \
  rtph264pay config-interval=1 ! \
  udpsink host=127.0.0.1 port=5000 sync=false async=false &
GSTREAMER_PID=$!

log_success "GStreamer started with PID: $GSTREAMER_PID"

# === STEP 7: Health Monitoring Setup ===
log_info "Starting health monitoring service..."
if [ -x /usr/local/bin/health-monitor.sh ]; then
  HEALTH_PORT=${HEALTH_PORT:-8080}
  /usr/local/bin/health-monitor.sh serve &
  HEALTH_PID=$!
  log_success "Health monitor started with PID: $HEALTH_PID on port $HEALTH_PORT"
else
  log_error "Health monitor script not found"
fi

# === STEP 8: Art Resource Watcher ===
if [ -x /usr/local/bin/watch_art_res.sh ]; then
  log_info "Starting art resource watcher..."
  /usr/local/bin/watch_art_res.sh &
  WATCHER_PID=$!
  log_success "Art watcher started with PID: $WATCHER_PID"
fi

# === Container Ready ===
log_success "Container setup complete!"
log_info "Services:"
log_info "  - VNC: localhost:5901"
log_info "  - Video stream: UDP port 5000"
log_info "  - Health monitor: HTTP port ${HEALTH_PORT:-8080}"
log_info "  - QEMU PID: $EMU_PID"
log_info "  - Xvfb PID: $XVFB_PID"
log_info "  - GStreamer PID: $GSTREAMER_PID"
if [ -n "${HEALTH_PID:-}" ]; then
  log_info "  - Health monitor PID: $HEALTH_PID"
fi

# Cleanup function
cleanup() {
  log_info "Received shutdown signal, cleaning up..."
  
  if [ -n "${HEALTH_PID:-}" ]; then
    log_info "Stopping health monitor (PID: $HEALTH_PID)"
    kill $HEALTH_PID 2>/dev/null || true
  fi
  
  if [ -n "${GSTREAMER_PID:-}" ]; then
    log_info "Stopping GStreamer (PID: $GSTREAMER_PID)"
    kill $GSTREAMER_PID 2>/dev/null || true
  fi
  
  if [ -n "${EMU_PID:-}" ]; then
    log_info "Stopping QEMU (PID: $EMU_PID)"
    kill $EMU_PID 2>/dev/null || true
  fi
  
  if [ -n "${XVFB_PID:-}" ]; then
    log_info "Stopping Xvfb (PID: $XVFB_PID)"
    kill $XVFB_PID 2>/dev/null || true
  fi

  if [ -n "${WATCHER_PID:-}" ]; then
    log_info "Stopping art watcher (PID: $WATCHER_PID)"
    kill $WATCHER_PID 2>/dev/null || true
  fi
  
  if [ -f "$SNAPSHOT_NAME" ]; then
    log_info "Removing snapshot file: $SNAPSHOT_NAME"
    rm -f "$SNAPSHOT_NAME" 2>/dev/null || true
  fi
  
  log_success "Cleanup complete"
  exit 0
}

trap cleanup SIGTERM SIGINT

log_info "Container is ready and waiting..."
wait $EMU_PID
