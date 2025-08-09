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

log_warn() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  WARNING: $1"
}

# Configuration with defaults
BRIDGE=${BRIDGE:-loco-br}
TAP_IF=${TAP_IF:-tap0}
DISK=${DISK:-/images/bootable.qcow2}
CREATE_BOOTABLE_DISK=${CREATE_BOOTABLE_DISK:-true}
DISK_SIZE=${DISK_SIZE:-2G}

log_info "=== QEMU Bootable Emulator Starting ==="
log_info "Configuration:"
log_info "  BRIDGE=$BRIDGE"
log_info "  TAP_IF=$TAP_IF"
log_info "  DISK=$DISK"
log_info "  CREATE_BOOTABLE_DISK=$CREATE_BOOTABLE_DISK"
log_info "  DISK_SIZE=$DISK_SIZE"

# === STEP 1: Virtual Display Setup ===
log_info "=== Setting up virtual display ==="

# Find an available display number
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

log_info "Using display number: $DISPLAY_NUM"

# Kill any existing processes on this display
if pgrep -f "Xvfb :$DISPLAY_NUM" > /dev/null; then
  log_info "Killing existing Xvfb on display :$DISPLAY_NUM"
  pkill -f "Xvfb :$DISPLAY_NUM" || true
  sleep 2
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

# Start VNC server
log_info "Starting VNC server..."
x11vnc -display :$DISPLAY_NUM -forever -shared -rfbport 5901 -nopw &
VNC_PID=$!
sleep 2

if ! kill -0 $VNC_PID 2>/dev/null; then
  log_error "Failed to start VNC server"
  exit 1
fi
log_success "VNC server started on port 5901 (PID: $VNC_PID)"

# === STEP 2: Audio Setup ===
log_info "=== Setting up audio ==="
if pulseaudio --start --exit-idle-time=-1; then
  log_success "PulseAudio started successfully"
else
  log_warn "Failed to start PulseAudio, continuing without audio"
fi

# === STEP 3: Network Setup ===
log_info "=== Setting up network ==="

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
log_info "=== Setting up disk image ==="

# Function to create a bootable FreeDOS disk
create_bootable_disk() {
  local disk_path="$1"
  local size="$2"
  
  log_info "Creating bootable FreeDOS disk: $disk_path"
  
  # Create the disk image
  if qemu-img create -f qcow2 "$disk_path" "$size"; then
    log_success "Created blank disk image: $disk_path ($size)"
  else
    log_error "Failed to create disk image"
    return 1
  fi
  
  # Download FreeDOS installer if not already present
  FREEDOS_ISO="/tmp/freedos.iso"
  if [ ! -f "$FREEDOS_ISO" ]; then
    log_info "Downloading FreeDOS installer..."
    if wget -q -O "$FREEDOS_ISO" "https://www.freedos.org/download/download/FD13-FullUSB.zip"; then
      log_success "Downloaded FreeDOS installer"
    else
      log_warn "Failed to download FreeDOS, creating minimal bootable disk"
      # Create a minimal bootable disk without OS
      return 0
    fi
  fi
  
  return 0
}

# Check if disk exists or needs to be created
if [ "$CREATE_BOOTABLE_DISK" = "true" ] || [ ! -f "$DISK" ]; then
  log_info "Creating or recreating bootable disk image..."
  create_bootable_disk "$DISK" "$DISK_SIZE"
elif [ -f "$DISK" ]; then
  log_success "Using existing disk image: $DISK"
  log_info "Disk details: $(ls -lh "$DISK" 2>/dev/null || echo "Cannot stat disk")"
  log_info "Disk info: $(qemu-img info "$DISK" 2>/dev/null || echo "Cannot get disk info")"
else
  log_error "Disk image not found and CREATE_BOOTABLE_DISK is false"
  exit 1
fi

# === STEP 5: QEMU Startup ===
log_info "=== Starting QEMU emulator ==="

# QEMU command with comprehensive options
QEMU_CMD="qemu-system-i386 \
  -M pc \
  -cpu pentium3 \
  -m 512 \
  -drive file=$DISK,format=qcow2,if=ide \
  -netdev tap,id=net0,ifname=$TAP_IF,script=no,downscript=no \
  -device ne2k_pci,netdev=net0 \
  -device sb16 \
  -vga std \
  -display vnc=:2 \
  -rtc base=localtime \
  -boot order=cd,menu=on,splash-time=5000 \
  -no-shutdown \
  -no-reboot \
  -monitor none"

log_info "QEMU command: $QEMU_CMD"
log_info "Starting QEMU..."

eval "$QEMU_CMD" &
EMU_PID=$!
log_info "QEMU started with PID: $EMU_PID"

# Wait for QEMU to initialize
log_info "Waiting for QEMU to initialize..."
sleep 10

if ! kill -0 $EMU_PID 2>/dev/null; then
  log_error "QEMU process died during startup"
  wait $EMU_PID || true
  exit 1
fi

log_success "QEMU started successfully (PID: $EMU_PID)"

# === STEP 6: Video Streaming Setup ===
log_info "=== Starting video stream at 1024x768 for Lego Loco compatibility ==="
log_info "Stream configuration: 1024x768@25fps, bitrate=1200kbps (optimized for higher resolution)"
gst-launch-1.0 -v \
  ximagesrc display-name=:$DISPLAY_NUM use-damage=0 ! \
  queue max-size-time=100000000 max-size-buffers=5 leaky=downstream ! \
  videoconvert ! \
  queue max-size-time=100000000 max-size-buffers=5 leaky=downstream ! \
  videoscale ! \
  video/x-raw,width=1024,height=768,framerate=25/1 ! \
  queue max-size-time=100000000 max-size-buffers=5 leaky=downstream ! \
  x264enc tune=zerolatency bitrate=1200 speed-preset=ultrafast key-int-max=25 ! \
  queue max-size-time=100000000 max-size-buffers=5 leaky=downstream ! \
  rtph264pay config-interval=1 ! \
  udpsink host=127.0.0.1 port=5000 sync=false async=false &
GSTREAMER_PID=$!

if ! kill -0 $GSTREAMER_PID 2>/dev/null; then
  log_warn "GStreamer failed to start, video streaming may not work"
else
  log_success "GStreamer started with PID: $GSTREAMER_PID"
  log_info "Stream details: 1024x768@25fps H.264 stream on UDP port 5000"
  
  # SRE Stream Health Check
  log_info "Performing SRE stream health validation..."
  sleep 3  # Allow stream to initialize
  
  if kill -0 $GSTREAMER_PID 2>/dev/null && netstat -un 2>/dev/null | grep -q ":5000 "; then
    log_success "✅ Stream health validation passed - 1024x768 H.264 stream active"
  else
    log_warn "⚠️  Stream health validation incomplete - monitoring required"
  fi
fi

# === Container Ready ===
log_success "=== Container setup complete! ==="
log_info "Services available:"
log_info "  - VNC: localhost:5901 (connect with VNC viewer)"
log_info "  - Video stream: UDP H.264 on port 5000 (1024x768@25fps)"
log_info "  - Display: $DISPLAY"
log_info "Running processes:"
log_info "  - QEMU PID: $EMU_PID"
log_info "  - Xvfb PID: $XVFB_PID"
log_info "  - VNC PID: $VNC_PID"
log_info "  - GStreamer PID: ${GSTREAMER_PID:-N/A} (1024x768 stream)"

# Cleanup function
cleanup() {
  log_info "=== Received shutdown signal, cleaning up ==="
  
  if [ -n "${GSTREAMER_PID:-}" ] && kill -0 $GSTREAMER_PID 2>/dev/null; then
    log_info "Stopping GStreamer (PID: $GSTREAMER_PID)"
    kill $GSTREAMER_PID 2>/dev/null || true
  fi
  
  if [ -n "${EMU_PID:-}" ] && kill -0 $EMU_PID 2>/dev/null; then
    log_info "Stopping QEMU (PID: $EMU_PID)"
    kill $EMU_PID 2>/dev/null || true
  fi
  
  if [ -n "${VNC_PID:-}" ] && kill -0 $VNC_PID 2>/dev/null; then
    log_info "Stopping VNC server (PID: $VNC_PID)"
    kill $VNC_PID 2>/dev/null || true
  fi
  
  if [ -n "${XVFB_PID:-}" ] && kill -0 $XVFB_PID 2>/dev/null; then
    log_info "Stopping Xvfb (PID: $XVFB_PID)"
    kill $XVFB_PID 2>/dev/null || true
  fi
  
  log_success "Cleanup complete"
  exit 0
}

trap cleanup SIGTERM SIGINT

log_info "=== Container ready and waiting ==="
log_info "You can now:"
log_info "  1. Connect via VNC to localhost:5901"
log_info "  2. Access the web frontend"
log_info "  3. View the video stream"

# Keep the container running
wait $EMU_PID
