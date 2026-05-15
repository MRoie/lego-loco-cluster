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

log_warning() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  WARNING: $1" >&2
}

# Configuration with defaults
BRIDGE=${BRIDGE:-loco-br}

# --- Instance Identity Derivation (K2 contract: POD_NAME via downward API) ---
# Priority: POD_NAME ordinal > INSTANCE_INDEX env > default 0
if [ -n "${POD_NAME:-}" ]; then
  INSTANCE_INDEX=${POD_NAME##*-}
fi
INSTANCE_INDEX=${INSTANCE_INDEX:-0}
GUEST_HOSTNAME=${GUEST_HOSTNAME:-LOCO-0${INSTANCE_INDEX}}
GUEST_IP=${GUEST_IP:-192.168.10.$((10 + INSTANCE_INDEX))}
GUEST_MAC=${GUEST_MAC:-52:54:00:10:00:0${INSTANCE_INDEX}}
TAP_IF=${TAP_IF:-tap${INSTANCE_INDEX}}
BRIDGE_IP=${BRIDGE_IP:-192.168.10.$((200 + INSTANCE_INDEX))}
GUEST_GATEWAY=${GUEST_GATEWAY:-$BRIDGE_IP}
GUEST_NETMASK=${GUEST_NETMASK:-255.255.255.0}
WORKGROUP=${WORKGROUP:-LOCOLAND}
POD_NAMESPACE=${POD_NAMESPACE:-loco}
EMULATOR_SERVICE_NAME=${EMULATOR_SERVICE_NAME:-loco-loco-emulator}
EMULATOR_REPLICAS=${EMULATOR_REPLICAS:-1}
ENABLE_GUEST_L2_MESH=${ENABLE_GUEST_L2_MESH:-true}
ENABLE_IDENTITY_FLOPPY=${ENABLE_IDENTITY_FLOPPY:-true}
ENABLE_IDENTITY_CD=${ENABLE_IDENTITY_CD:-false}
ENABLE_GUEST_DHCP=${ENABLE_GUEST_DHCP:-true}
DHCP_SERVER_INDEX=${DHCP_SERVER_INDEX:-0}
VXLAN_ID=${VXLAN_ID:-42}
VXLAN_PORT=${VXLAN_PORT:-4789}
VXLAN_IF=${VXLAN_IF:-vxlan${INSTANCE_INDEX}}
MESH_RECONCILE_INTERVAL=${MESH_RECONCILE_INTERVAL:-5}
MESH_RECONCILE_STEADY_INTERVAL=${MESH_RECONCILE_STEADY_INTERVAL:-30}
QEMU_CPU=${QEMU_CPU:-qemu32,+sse3,+ssse3,+sse4.1}
QEMU_ACCEL=${QEMU_ACCEL:-auto}
QEMU_TCG_OPTS=${QEMU_TCG_OPTS:-thread=multi,tb-size=1024}
QEMU_KVM_OPTS=${QEMU_KVM_OPTS:-}
QEMU_MEMORY=${QEMU_MEMORY:-512}
QEMU_SMP=${QEMU_SMP:-1}
QEMU_EXTRA_ARGS=${QEMU_EXTRA_ARGS:-}
CDROM_MODE=${CDROM_MODE:-softgpu}

DISK=${DISK:-/images/win98.qcow2}
SNAPSHOT_REGISTRY=${SNAPSHOT_REGISTRY:-ghcr.io/mroie/qemu-snapshots}
SNAPSHOT_TAG=${SNAPSHOT_TAG:-win98-base}
USE_PREBUILT_SNAPSHOT=${USE_PREBUILT_SNAPSHOT:-true}

log_info "Starting QEMU emulator container with configuration:"
log_info "  INSTANCE_INDEX=$INSTANCE_INDEX (from POD_NAME=${POD_NAME:-<unset>})"
log_info "  GUEST_HOSTNAME=$GUEST_HOSTNAME"
log_info "  GUEST_IP=$GUEST_IP"
log_info "  GUEST_MAC=$GUEST_MAC"
log_info "  BRIDGE=$BRIDGE"
log_info "  BRIDGE_IP=$BRIDGE_IP"
log_info "  TAP_IF=$TAP_IF"
log_info "  POD_IP=${POD_IP:-<unset>}"
log_info "  POD_NAMESPACE=$POD_NAMESPACE"
log_info "  EMULATOR_SERVICE_NAME=$EMULATOR_SERVICE_NAME"
log_info "  EMULATOR_REPLICAS=$EMULATOR_REPLICAS"
log_info "  QEMU_CPU=$QEMU_CPU"
log_info "  QEMU_ACCEL=$QEMU_ACCEL"
log_info "  QEMU_TCG_OPTS=$QEMU_TCG_OPTS"
log_info "  QEMU_KVM_OPTS=$QEMU_KVM_OPTS"
log_info "  QEMU_MEMORY=$QEMU_MEMORY"
log_info "  QEMU_SMP=$QEMU_SMP"
log_info "  CDROM_MODE=$CDROM_MODE"
log_info "  DISK=$DISK"
log_info "  USE_PREBUILT_SNAPSHOT=$USE_PREBUILT_SNAPSHOT"
log_info "  SNAPSHOT_REGISTRY=$SNAPSHOT_REGISTRY"
log_info "  SNAPSHOT_TAG=$SNAPSHOT_TAG"

disable_bridge_netfilter() {
  if [ -w /proc/sys/net/bridge/bridge-nf-call-iptables ]; then
    echo 0 > /proc/sys/net/bridge/bridge-nf-call-iptables || true
  fi
  if [ -w /proc/sys/net/bridge/bridge-nf-call-ip6tables ]; then
    echo 0 > /proc/sys/net/bridge/bridge-nf-call-ip6tables || true
  fi
}

reconcile_guest_l2_mesh_peers() {
  local missing=0
  local added=0
  local desired_peer_ips=""

  for peer_index in $(seq 0 $((EMULATOR_REPLICAS - 1))); do
    if [ "$peer_index" = "$INSTANCE_INDEX" ]; then
      continue
    fi

    local peer_host="${EMULATOR_SERVICE_NAME}-${peer_index}.${EMULATOR_SERVICE_NAME}.${POD_NAMESPACE}.svc.cluster.local"
    local peer_ip
    peer_ip=$(getent hosts "$peer_host" | awk 'NR==1 { print $1 }')
    if [ -z "$peer_ip" ]; then
      missing=$((missing + 1))
      log_warning "Unable to resolve peer $peer_host for guest mesh"
      continue
    fi

    desired_peer_ips="${desired_peer_ips} ${peer_ip}"

    if bridge fdb show dev "$VXLAN_IF" | grep -q "00:00:00:00:00:00 dst $peer_ip"; then
      continue
    fi

    if bridge fdb append 00:00:00:00:00:00 dev "$VXLAN_IF" dst "$peer_ip" 2>/dev/null; then
      added=$((added + 1))
      log_info "Guest mesh peer added: $peer_host -> $peer_ip"
    else
      missing=$((missing + 1))
      log_warning "Failed to add guest mesh peer: $peer_host -> $peer_ip"
    fi
  done

  bridge fdb show dev "$VXLAN_IF" | awk '/00:00:00:00:00:00 dst/ {
    for (i = 1; i <= NF; i++) {
      if ($i == "dst") {
        print $(i + 1)
      }
    }
  }' | while read -r existing_peer_ip; do
    case " ${desired_peer_ips} " in
      *" ${existing_peer_ip} "*) ;;
      *)
        if bridge fdb del 00:00:00:00:00:00 dev "$VXLAN_IF" dst "$existing_peer_ip" 2>/dev/null; then
          log_info "Pruned stale guest mesh peer: $existing_peer_ip"
        fi
        ;;
    esac
  done

  if [ "$added" -gt 0 ] || [ "$missing" -gt 0 ]; then
    log_info "Guest mesh reconcile result: added=$added missing=$missing"
  fi

  [ "$missing" -eq 0 ]
}

setup_guest_l2_mesh() {
  if [ "$ENABLE_GUEST_L2_MESH" != "true" ]; then
    log_info "Guest L2 mesh disabled"
    return
  fi

  if [ -z "${POD_IP:-}" ]; then
    log_warning "POD_IP not set; skipping guest L2 mesh setup"
    return
  fi

  if [ "$EMULATOR_REPLICAS" -le 1 ] 2>/dev/null; then
    log_info "Single emulator replica; no guest L2 mesh needed"
    return
  fi

  log_info "Setting up VXLAN guest mesh on $VXLAN_IF"
  ip link delete "$VXLAN_IF" 2>/dev/null || true
  if ! ip link add "$VXLAN_IF" type vxlan id "$VXLAN_ID" dstport "$VXLAN_PORT" local "$POD_IP"; then
    log_warning "Failed to create VXLAN interface $VXLAN_IF (kernel module missing?); skipping guest L2 mesh"
    return
  fi
  ip link set "$VXLAN_IF" master "$BRIDGE" 2>/dev/null || log_warning "Failed to add $VXLAN_IF to bridge $BRIDGE"
  ip link set "$VXLAN_IF" up 2>/dev/null || log_warning "Failed to bring up $VXLAN_IF"

  (
    set +e
    while true; do
      if reconcile_guest_l2_mesh_peers; then
        sleep "$MESH_RECONCILE_STEADY_INTERVAL"
      else
        sleep "$MESH_RECONCILE_INTERVAL"
      fi
    done
  ) &
  MESH_PID=$!
  log_success "Guest L2 mesh reconciler started (PID: $MESH_PID)"
}

start_guest_dhcp() {
  if [ "$ENABLE_GUEST_DHCP" != "true" ]; then
    log_info "Guest DHCP disabled"
    return
  fi

  if [ "$INSTANCE_INDEX" != "$DHCP_SERVER_INDEX" ]; then
    log_info "Guest DHCP server runs on instance $DHCP_SERVER_INDEX; skipping on $INSTANCE_INDEX"
    return
  fi

  log_info "Starting guest DHCP server on $BRIDGE"
  DHCP_SERVER_IP="$BRIDGE_IP" /usr/local/bin/mini_dhcp.py "$BRIDGE" &
  DHCP_PID=$!
  log_success "Guest DHCP server started (PID: $DHCP_PID)"
}

create_identity_floppy() {
  FLOPPY_OPT=""
  IDENTITY_CD_OPT=""

  if [ "$ENABLE_IDENTITY_FLOPPY" != "true" ]; then
    log_info "Identity floppy disabled"
    return
  fi

  if ! command -v mkfs.fat >/dev/null 2>&1 || ! command -v mcopy >/dev/null 2>&1; then
    log_warning "mkfs.fat or mcopy missing; skipping identity floppy generation"
    return
  fi

  local identity_dir="/tmp/identity-${INSTANCE_INDEX}"
  local identity_img="/tmp/identity-${INSTANCE_INDEX}.img"
  local identity_iso="/tmp/identity-${INSTANCE_INDEX}.iso"
  rm -rf "$identity_dir"
  mkdir -p "$identity_dir"

  /usr/local/bin/customize-win98-instance.sh "$INSTANCE_INDEX" "$identity_dir"

  dd if=/dev/zero of="$identity_img" bs=1024 count=1440 status=none
  mkfs.fat -F 12 "$identity_img" >/dev/null 2>&1
  mcopy -i "$identity_img" -o "$identity_dir/LOCO-ID.REG" ::LOCO-ID.REG
  mcopy -i "$identity_img" -o "$identity_dir/LOCO-ID.BAT" ::LOCO-ID.BAT
  mcopy -i "$identity_img" -o "$identity_dir/LMHOSTS" ::LMHOSTS
  mcopy -i "$identity_img" -o "$identity_dir/AUTORUN.INF" ::AUTORUN.INF

  FLOPPY_OPT="-drive file=$identity_img,format=raw,if=floppy,index=0"
  log_success "Created Win98 identity floppy for $GUEST_HOSTNAME at $identity_img"

  if [ "$ENABLE_IDENTITY_CD" != "true" ]; then
    log_info "Identity CD-ROM disabled; keeping primary CD-ROM available for SoftGPU"
  elif command -v genisoimage >/dev/null 2>&1; then
    genisoimage -quiet -J -r -V "LOCOID${INSTANCE_INDEX}" -o "$identity_iso" "$identity_dir"
    IDENTITY_CD_OPT="-drive file=$identity_iso,format=raw,media=cdrom,readonly=on,if=ide,index=2"
    log_success "Created Win98 identity CD-ROM for $GUEST_HOSTNAME at $identity_iso"
  else
    log_warning "genisoimage missing; skipping identity CD-ROM generation"
  fi
}

create_mmx_patch_iso() {
  if [ ! -f /opt/softgpu.iso ]; then
    log_warning "SoftGPU ISO missing; cannot create MMX patch ISO"
    return 1
  fi

  local patch_dir="/tmp/mmxpatch"
  local patch_iso="/tmp/mmxpatch.iso"
  rm -rf "$patch_dir"
  mkdir -p "$patch_dir"

  extract_mmx_file() {
    isoinfo -R -i /opt/softgpu.iso -x "/$1" > "$patch_dir/$2"
  }

  extract_mmx_file driver/mmx-w95/wined3d.dll WINED3D.DLL
  extract_mmx_file driver/mmx-w95/wined8.dll WINED8.DLL
  extract_mmx_file driver/mmx-w95/wined9.dll WINED9.DLL
  extract_mmx_file driver/mmx-w95/winedd.dll WINEDD.DLL
  extract_mmx_file extras/wine/mmx/d3d8_98.dll D3D8.DLL
  extract_mmx_file extras/wine/mmx/d3d9_98.dll D3D9.DLL
  extract_mmx_file extras/wine/mmx/ddraw_95.dll DD95.DLL
  extract_mmx_file extras/wine/mmx/ddraw_98.dll DD98.DLL
  extract_mmx_file extras/wine/mmx/ddraw_98.dll DDRAW.DLL
  extract_mmx_file extras/wine/mmx/ddraw_98.dll DDRAWM.DLL
  extract_mmx_file extras/wine/mmx/ddraw_xp.dll DDXP.DLL

  cp "$patch_dir/WINEDD.DLL" "$patch_dir/DDSYS.DLL"
  cp "$patch_dir/WINED8.DLL" "$patch_dir/MSD3D8.DLL"
  cp "$patch_dir/WINED9.DLL" "$patch_dir/MSD3D9.DLL"
  cp "$patch_dir/WINEDD.DLL" "$patch_dir/MSDDRAW.DLL"
  cp "$patch_dir/WINEDD.DLL" "$patch_dir/MSDDSYS.DLL"

  cat > "$patch_dir/PATCH.BAT" <<'EOF'
@ECHO OFF
ECHO Applying Loco MMX WineD3D patch > C:\MMXPATCH.LOG
COPY /Y D:\WINED3D.DLL C:\WINDOWS\SYSTEM\WINED3D.DLL >> C:\MMXPATCH.LOG
COPY /Y D:\WINED8.DLL C:\WINDOWS\SYSTEM\WINED8.DLL >> C:\MMXPATCH.LOG
COPY /Y D:\WINED9.DLL C:\WINDOWS\SYSTEM\WINED9.DLL >> C:\MMXPATCH.LOG
COPY /Y D:\WINEDD.DLL C:\WINDOWS\SYSTEM\WINEDD.DLL >> C:\MMXPATCH.LOG
COPY /Y D:\D3D8.DLL C:\WINDOWS\SYSTEM\D3D8.DLL >> C:\MMXPATCH.LOG
COPY /Y D:\D3D9.DLL C:\WINDOWS\SYSTEM\D3D9.DLL >> C:\MMXPATCH.LOG
COPY /Y D:\DDRAW.DLL C:\WINDOWS\SYSTEM\DDRAW.DLL >> C:\MMXPATCH.LOG
COPY /Y D:\DDRAWM.DLL C:\WINDOWS\SYSTEM\DDRAWM.DLL >> C:\MMXPATCH.LOG
COPY /Y D:\DD95.DLL C:\WINDOWS\SYSTEM\DD95.DLL >> C:\MMXPATCH.LOG
COPY /Y D:\DD98.DLL C:\WINDOWS\SYSTEM\DD98.DLL >> C:\MMXPATCH.LOG
COPY /Y D:\DDXP.DLL C:\WINDOWS\SYSTEM\DDXP.DLL >> C:\MMXPATCH.LOG
COPY /Y D:\DDSYS.DLL C:\WINDOWS\SYSTEM\DDSYS.DLL >> C:\MMXPATCH.LOG
COPY /Y D:\MSD3D8.DLL C:\WINDOWS\SYSTEM\MSD3D8.DLL >> C:\MMXPATCH.LOG
COPY /Y D:\MSD3D9.DLL C:\WINDOWS\SYSTEM\MSD3D9.DLL >> C:\MMXPATCH.LOG
COPY /Y D:\MSDDRAW.DLL C:\WINDOWS\SYSTEM\MSDDRAW.DLL >> C:\MMXPATCH.LOG
COPY /Y D:\MSDDSYS.DLL C:\WINDOWS\SYSTEM\MSDDSYS.DLL >> C:\MMXPATCH.LOG
ECHO OK > C:\MMXPATCH.OK
EOF

  sed -i 's/$/\r/' "$patch_dir/PATCH.BAT"
  genisoimage -quiet -J -r -V MMXPATCH -o "$patch_iso" "$patch_dir"
  log_success "Created MMX WineD3D patch ISO at $patch_iso"
}

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

if ip addr add "$BRIDGE_IP/24" dev "$BRIDGE"; then
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

disable_bridge_netfilter

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
setup_guest_l2_mesh
start_guest_dhcp

# === STEP 4: Disk Image Setup ===
# Use a persistent per-instance snapshot on PVC to preserve guest state across restarts
SNAPSHOT_NAME="/images/win98_instance_${INSTANCE_INDEX}.qcow2"
SKIP_SNAPSHOT_CREATION=false

# Reuse existing persistent snapshot if present
if [ -f "$SNAPSHOT_NAME" ]; then
  log_success "Reusing persistent snapshot: $SNAPSHOT_NAME"
  log_info "Snapshot details: $(ls -lh "$SNAPSHOT_NAME")"
  SKIP_SNAPSHOT_CREATION=true
fi

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
  
  # PVC-first strategy: Check for disk image in PVC-mounted directory first
  DISK_FOUND=false
  DISK_SOURCE=""
  
  # Check if PVC-mounted disk image exists
  if [ -f "$DISK" ]; then
    log_success "✅ PVC-mounted disk image found: $DISK"
    log_info "File details: $(ls -lh "$DISK")"
    DISK_FOUND=true
    DISK_SOURCE="PVC"
  else
    log_warning "⚠️  PVC-mounted disk image not found: $DISK"
    log_info "Available files in /images:"
    ls -la /images/ 2>/dev/null || log_error "/images directory not accessible"
    
    # Fallback to built-in disk image
    BUILTIN_DISK="/opt/builtin-images/win98.qcow2.builtin"
    if [ -f "$BUILTIN_DISK" ]; then
      log_success "✅ Built-in disk image found: $BUILTIN_DISK"
      log_info "File details: $(ls -lh "$BUILTIN_DISK")"
      DISK_FOUND=true
      DISK_SOURCE="builtin"
      DISK="$BUILTIN_DISK"
    else
      log_error "❌ Neither PVC-mounted nor built-in disk image found"
      log_info "Available files in /images:"
      ls -la /images/ 2>/dev/null || log_error "/images directory not accessible"
      log_info "Available files in /tmp:"
      ls -la /tmp/ 2>/dev/null || log_error "/tmp directory not accessible"
      exit 1
    fi
  fi
  
  if [ "$DISK_FOUND" = true ]; then
    log_info "Creating QCOW2 snapshot from $DISK_SOURCE disk image: $DISK"
    if qemu-img create -f qcow2 -b "$DISK" -F qcow2 "$SNAPSHOT_NAME"; then
      log_success "✅ Snapshot created successfully from $DISK_SOURCE disk"
      log_info "Snapshot details: $(ls -lh "$SNAPSHOT_NAME")"
    else
      log_error "❌ Failed to create snapshot from $DISK_SOURCE disk"
      exit 1
    fi
  fi
else
  log_success "Using pre-built snapshot: $SNAPSHOT_NAME"
  log_info "Snapshot details: $(ls -lh "$SNAPSHOT_NAME")"
fi

# === STEP 5: QEMU Startup ===
log_info "Starting QEMU emulator..."

# Auto-detect KVM or fall back to TCG
ACCEL_FLAG="-accel tcg"
if [ -e /dev/kvm ] && [ -w /dev/kvm ]; then
  ACCEL_FLAG="-accel kvm"
  log_info "KVM acceleration available — using KVM"
else
  log_info "KVM not available — using TCG (software emulation)"
fi

# Honor QEMU_ACCEL after the basic probe above. KVM is the difference between
# "survives" and "smooth" for SoftGPU; tuned TCG is only the fallback.
if [ -e /dev/kvm ] && [ -w /dev/kvm ]; then
  KVM_AVAILABLE=true
else
  KVM_AVAILABLE=false
fi

case "$QEMU_ACCEL" in
  kvm)
    if [ "$KVM_AVAILABLE" != "true" ]; then
      log_error "QEMU_ACCEL=kvm requested, but /dev/kvm is not available in this pod"
      exit 1
    fi
    ACCEL_FLAG="-accel kvm${QEMU_KVM_OPTS:+,$QEMU_KVM_OPTS}"
    log_info "KVM acceleration requested and available"
    ;;
  tcg)
    ACCEL_FLAG="-accel tcg${QEMU_TCG_OPTS:+,$QEMU_TCG_OPTS}"
    log_info "TCG software emulation requested with opts: ${QEMU_TCG_OPTS:-<none>}"
    ;;
  auto)
    if [ "$KVM_AVAILABLE" = "true" ]; then
      ACCEL_FLAG="-accel kvm${QEMU_KVM_OPTS:+,$QEMU_KVM_OPTS}"
      log_info "KVM acceleration available; using KVM"
    else
      ACCEL_FLAG="-accel tcg${QEMU_TCG_OPTS:+,$QEMU_TCG_OPTS}"
      log_warning "KVM not available; using tuned TCG software emulation"
    fi
    ;;
  *)
    log_error "Unsupported QEMU_ACCEL=$QEMU_ACCEL (expected auto, kvm, or tcg)"
    exit 1
    ;;
esac

# Determine CD-ROM option (SoftGPU ISO for VMware SVGA driver)
SOFTGPU_CD_OPT=""
if [ "$CDROM_MODE" = "mmxpatch" ]; then
  if create_mmx_patch_iso; then
    SOFTGPU_CD_OPT="-cdrom /tmp/mmxpatch.iso"
    log_info "MMX patch ISO mounted as CD-ROM"
  fi
elif [ -f /opt/softgpu.iso ]; then
  SOFTGPU_CD_OPT="-cdrom /opt/softgpu.iso"
  log_info "SoftGPU ISO found, mounting as CD-ROM"
fi

create_identity_floppy

if [ -n "${IDENTITY_CD_OPT:-}" ] && [ -f /opt/softgpu.iso ]; then
  SOFTGPU_CD_OPT="-drive file=/opt/softgpu.iso,format=raw,media=cdrom,readonly=on,if=ide,index=3"
  log_info "Identity CD-ROM is primary; SoftGPU ISO moved to secondary CD-ROM"
fi

log_info "QEMU command: qemu-system-i386 $ACCEL_FLAG -M pc -cpu $QEMU_CPU -m $QEMU_MEMORY -smp $QEMU_SMP -hda $SNAPSHOT_NAME -vga vmware -qmp unix:/tmp/qemu-qmp.sock ..."

# Add debugging to see what we're actually booting from
log_info "Checking disk image contents..."
qemu-img info "$SNAPSHOT_NAME" | while read line; do log_info "  $line"; done

qemu-system-i386 \
  $ACCEL_FLAG \
  -M pc -cpu "$QEMU_CPU" \
  -m "$QEMU_MEMORY" -smp "$QEMU_SMP" -hda "$SNAPSHOT_NAME" \
  -net nic,model=ne2k_pci,macaddr=$GUEST_MAC -net tap,ifname=$TAP_IF,script=no,downscript=no \
  -device sb16,audiodev=snd0 \
  -vga vmware -display vnc=0.0.0.0:1 \
  $FLOPPY_OPT \
  $IDENTITY_CD_OPT \
  $SOFTGPU_CD_OPT \
  -audiodev pa,id=snd0 \
  -rtc base=localtime \
  -no-reboot \
  -boot order=c,menu=on \
  -qmp unix:/tmp/qemu-qmp.sock,server,nowait \
  -monitor none \
  $QEMU_EXTRA_ARGS &

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
log_info "Starting GStreamer video stream at 1024x768 for Lego Loco compatibility..."
log_info "Stream configuration: VP8 via VNC capture (rfbsrc), 1024x768, bitrate=1200kbps"
log_info "Note: Using rfbsrc to capture from QEMU VNC display (not ximagesrc/Xvfb which is empty)"
gst-launch-1.0 -v \
  rfbsrc host=127.0.0.1 port=5901 ! \
  queue max-size-time=100000000 max-size-buffers=5 leaky=downstream ! \
  videoconvert ! \
  queue max-size-time=100000000 max-size-buffers=5 leaky=downstream ! \
  videoscale ! \
  video/x-raw,width=1024,height=768 ! \
  queue max-size-time=100000000 max-size-buffers=5 leaky=downstream ! \
  vp8enc deadline=1 target-bitrate=1200000 keyframe-max-dist=25 cpu-used=8 ! \
  queue max-size-time=100000000 max-size-buffers=5 leaky=downstream ! \
  rtpvp8pay ! \
  udpsink host=${VIDEO_DEST_HOST:-127.0.0.1} port=${VIDEO_DEST_PORT:-5000} sync=false async=false &
GSTREAMER_PID=$!

log_success "GStreamer video started with PID: $GSTREAMER_PID"
log_info "Stream details: 1024x768 VP8 stream via rfbsrc→rtpvp8pay on UDP port ${VIDEO_DEST_PORT:-5000}"

# === STEP 6b: Audio Streaming Setup ===
log_info "Starting GStreamer audio stream (PulseAudio → Opus → RTP)..."
AUDIO_DEST_HOST=${AUDIO_DEST_HOST:-${VIDEO_DEST_HOST:-127.0.0.1}}
AUDIO_DEST_PORT=${AUDIO_DEST_PORT:-5001}

# Wait for PulseAudio to have a source (QEMU sb16 sink creates a monitor source)
AUDIO_WAIT=0
AUDIO_WAIT_MAX=30
log_info "Waiting for PulseAudio source from QEMU (max ${AUDIO_WAIT_MAX}s)..."
while [ $AUDIO_WAIT -lt $AUDIO_WAIT_MAX ]; do
  if pactl list sources short 2>/dev/null | grep -qE 'RUNNING|IDLE|SUSPENDED'; then
    log_success "PulseAudio source detected after ${AUDIO_WAIT}s"
    break
  fi
  AUDIO_WAIT=$((AUDIO_WAIT + 2))
  sleep 2
done
if [ $AUDIO_WAIT -ge $AUDIO_WAIT_MAX ]; then
  log_warning "No PulseAudio source detected after ${AUDIO_WAIT_MAX}s — audio pipeline may produce silence"
fi

gst-launch-1.0 -v \
  pulsesrc ! \
  queue max-size-time=100000000 max-size-buffers=10 leaky=downstream ! \
  audioconvert ! \
  audioresample ! \
  audio/x-raw,rate=48000,channels=2 ! \
  opusenc bitrate=64000 frame-size=20 ! \
  rtpopuspay pt=97 ! \
  udpsink host=${AUDIO_DEST_HOST} port=${AUDIO_DEST_PORT} sync=false async=false &
GSTREAMER_AUDIO_PID=$!

log_success "GStreamer audio started with PID: $GSTREAMER_AUDIO_PID"
log_info "Audio stream: Opus 48kHz stereo on UDP port ${AUDIO_DEST_PORT}"

# === STEP 7: Stream Health Monitoring (SRE Principles) ===
log_info "Implementing SRE monitoring for stream reliability..."

# Stream validation function
validate_stream_health() {
  local check_count=0
  local max_checks=5
  
  log_info "Validating stream health..."
  
  while [ $check_count -lt $max_checks ]; do
    if kill -0 $GSTREAMER_PID 2>/dev/null; then
      log_success "✅ GStreamer process is running (PID: $GSTREAMER_PID)"
      
      # Check if UDP port is active (remote or local)
      local dest_port=${VIDEO_DEST_PORT:-5000}
      if netstat -un 2>/dev/null | grep -q ":$dest_port "; then
        log_success "✅ UDP stream to port $dest_port is active"
        return 0
      else
        # Fallback check: just check process if netstat is elusive
        log_info "⏳ Waiting for UDP stream (port $dest_port) to initialize..."
      fi
    else
      log_error "❌ GStreamer process died (PID: $GSTREAMER_PID)"
      return 1
    fi
    
    check_count=$((check_count + 1))
    sleep 2
  done
  
  log_warning "⚠️  Stream validation incomplete after $max_checks checks"
  return 1
}

# Run stream validation
if validate_stream_health; then
  log_success "🎯 Stream health validation passed - 1024x768 H.264 stream ready"
else
  log_warning "⚠️  Stream health validation failed - stream may be unstable"
fi

# === STEP 8: Health Monitoring Setup ===
log_info "Starting health monitoring service..."
if [ -x /usr/local/bin/health-monitor.sh ]; then
  HEALTH_PORT=${HEALTH_PORT:-8080}
  /usr/local/bin/health-monitor.sh serve &
  HEALTH_PID=$!
  log_success "Health monitor started with PID: $HEALTH_PID on port $HEALTH_PORT"
else
  log_error "Health monitor script not found"
fi

# === STEP 9: Art Resource Watcher ===
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
log_info "  - Video stream: UDP port ${VIDEO_DEST_PORT:-5000} (1024x768@25fps H.264)"
log_info "  - Audio stream: UDP port ${AUDIO_DEST_PORT:-5001} (Opus 48kHz stereo)"
log_info "  - Health monitor: HTTP port ${HEALTH_PORT:-8080}"
log_info "  - QEMU PID: $EMU_PID"
log_info "  - Xvfb PID: $XVFB_PID"
log_info "  - GStreamer Video PID: $GSTREAMER_PID (1024x768 stream)"
log_info "  - GStreamer Audio PID: $GSTREAMER_AUDIO_PID (Opus stream)"
if [ -n "${HEALTH_PID:-}" ]; then
  log_info "  - Health monitor PID: $HEALTH_PID"
fi
if [ -n "${DHCP_PID:-}" ]; then
  log_info "  - Guest DHCP PID: $DHCP_PID"
fi

# Cleanup function
cleanup() {
  log_info "Received shutdown signal, cleaning up..."
  
  if [ -n "${HEALTH_PID:-}" ]; then
    log_info "Stopping health monitor (PID: $HEALTH_PID)"
    kill $HEALTH_PID 2>/dev/null || true
  fi
  
  if [ -n "${GSTREAMER_PID:-}" ]; then
    log_info "Stopping GStreamer video (PID: $GSTREAMER_PID)"
    kill $GSTREAMER_PID 2>/dev/null || true
  fi
  
  if [ -n "${GSTREAMER_AUDIO_PID:-}" ]; then
    log_info "Stopping GStreamer audio (PID: $GSTREAMER_AUDIO_PID)"
    kill $GSTREAMER_AUDIO_PID 2>/dev/null || true
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

  if [ -n "${MESH_PID:-}" ]; then
    log_info "Stopping guest L2 mesh reconciler (PID: $MESH_PID)"
    kill $MESH_PID 2>/dev/null || true
  fi

  if [ -n "${DHCP_PID:-}" ]; then
    log_info "Stopping guest DHCP server (PID: $DHCP_PID)"
    kill $DHCP_PID 2>/dev/null || true
  fi
  
  # Persistent snapshot: do NOT delete — preserves guest state across restarts
  # if [ -f "$SNAPSHOT_NAME" ]; then
  #   log_info "Removing snapshot file: $SNAPSHOT_NAME"
  #   rm -f "$SNAPSHOT_NAME" 2>/dev/null || true
  # fi
  
  log_success "Cleanup complete"
  exit 0
}

trap cleanup SIGTERM SIGINT

log_info "Container is ready and waiting..."
wait $EMU_PID
