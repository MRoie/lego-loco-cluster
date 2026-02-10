#!/usr/bin/env bash
# ============================================================================
# Shared L2 Virtual Network Setup for QEMU Guests
# ============================================================================
# Replaces isolated per-container bridges with a shared L2 segment so all
# Win98 guests reside on the same broadcast domain for DirectPlay LAN games.
#
# NETWORK_MODE values:
#   socket  - QEMU socket networking (default, zero infra changes)
#   vxlan   - VXLAN overlay between containers
#   macvlan - Multus macvlan (K8s only)
#   user    - QEMU user-mode NAT (isolated, no LAN play)
#   bridge  - Legacy isolated bridge (original behaviour)
# ============================================================================
set -euo pipefail

# Logging helpers (reuse from entrypoint if sourced, otherwise define)
if ! command -v log_info &>/dev/null; then
  log_info()    { echo "[$(date +'%Y-%m-%d %H:%M:%S')] ℹ️  INFO: $1"; }
  log_success() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] ✅ SUCCESS: $1"; }
  log_error()   { echo "[$(date +'%Y-%m-%d %H:%M:%S')] ❌ ERROR: $1" >&2; }
  log_warning() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  WARNING: $1" >&2; }
fi

# Configuration
NETWORK_MODE=${NETWORK_MODE:-socket}
BRIDGE=${BRIDGE:-loco-br}
TAP_IF=${TAP_IF:-tap0}
INSTANCE_ID=${INSTANCE_ID:-0}
SOCKET_MASTER_HOST=${SOCKET_MASTER_HOST:-loco-emulator-0}
SOCKET_PORT=${SOCKET_PORT:-4444}
VXLAN_VNI=${VXLAN_VNI:-42}
VXLAN_GROUP=${VXLAN_GROUP:-239.1.1.1}

# Compute unique guest IP: 192.168.10.(10 + INSTANCE_ID)
GUEST_IP="192.168.10.$((10 + INSTANCE_ID))"
BRIDGE_IP="192.168.10.1"
SUBNET="192.168.10.0/24"

log_info "Network setup: mode=$NETWORK_MODE instance=$INSTANCE_ID guest_ip=$GUEST_IP"

# ---------------------------------------------------------------
# Helper: create local bridge + TAP and attach QEMU
# ---------------------------------------------------------------
setup_bridge_and_tap() {
  log_info "Creating bridge $BRIDGE and TAP $TAP_IF ..."

  # Clean up existing
  ip link show "$TAP_IF" &>/dev/null && ip link delete "$TAP_IF" || true
  ip link show "$BRIDGE" &>/dev/null && ip link delete "$BRIDGE" || true

  ip link add name "$BRIDGE" type bridge
  ip addr add "${BRIDGE_IP}/24" dev "$BRIDGE" || true
  ip link set "$BRIDGE" up

  ip tuntap add "$TAP_IF" mode tap
  ip link set "$TAP_IF" master "$BRIDGE"
  ip link set "$TAP_IF" up

  # Enable IP forwarding so the bridge can act as a gateway
  echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || true

  log_success "Bridge $BRIDGE + TAP $TAP_IF ready"
}

# ---------------------------------------------------------------
# MODE: socket — QEMU socket networking (shared L2)
# ---------------------------------------------------------------
setup_socket_network() {
  log_info "Setting up QEMU socket networking (shared L2)"

  # We still need a bridge + TAP for the guest NIC
  setup_bridge_and_tap

  # Build the QEMU -netdev argument for socket mode
  if [ "$INSTANCE_ID" -eq 0 ]; then
    # Instance 0 is the socket master (listen)
    QEMU_NET_ARGS="-netdev socket,id=lan0,listen=:${SOCKET_PORT} -device ne2k_pci,netdev=lan0"
    log_info "Socket master: listening on port $SOCKET_PORT"
  else
    # Other instances connect to the master
    QEMU_NET_ARGS="-netdev socket,id=lan0,connect=${SOCKET_MASTER_HOST}:${SOCKET_PORT} -device ne2k_pci,netdev=lan0"
    log_info "Socket client: connecting to $SOCKET_MASTER_HOST:$SOCKET_PORT"
  fi

  # Also keep TAP for host-guest communication (health checks, etc.)
  QEMU_NET_ARGS="${QEMU_NET_ARGS} -net nic,model=rtl8139 -net tap,ifname=${TAP_IF},script=no,downscript=no"

  log_success "Socket network configured for instance $INSTANCE_ID"
}

# ---------------------------------------------------------------
# MODE: vxlan — VXLAN overlay between containers
# ---------------------------------------------------------------
setup_vxlan_network() {
  log_info "Setting up VXLAN overlay network (VNI=$VXLAN_VNI)"

  setup_bridge_and_tap

  # Determine the container's eth0 IP for VXLAN endpoint
  LOCAL_IP=$(ip -4 addr show eth0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
  if [ -z "$LOCAL_IP" ]; then
    log_error "Cannot determine container IP for VXLAN"
    return 1
  fi

  # Create VXLAN interface and attach to bridge
  VXLAN_IF="vxlan${VXLAN_VNI}"
  ip link show "$VXLAN_IF" &>/dev/null && ip link delete "$VXLAN_IF" || true

  ip link add "$VXLAN_IF" type vxlan id "$VXLAN_VNI" \
    group "$VXLAN_GROUP" dev eth0 dstport 4789
  ip link set "$VXLAN_IF" master "$BRIDGE"
  ip link set "$VXLAN_IF" up

  # Standard TAP-based QEMU networking
  QEMU_NET_ARGS="-net nic,model=ne2k_pci -net tap,ifname=${TAP_IF},script=no,downscript=no"

  log_success "VXLAN overlay $VXLAN_IF attached to $BRIDGE"
}

# ---------------------------------------------------------------
# MODE: macvlan — Multus macvlan (secondary K8s interface)
# ---------------------------------------------------------------
setup_macvlan_network() {
  log_info "Setting up macvlan network"

  # Expect net1 interface from Multus
  if ip link show net1 &>/dev/null; then
    setup_bridge_and_tap

    # Attach the Multus interface to the bridge
    ip link set net1 master "$BRIDGE" || true
    ip link set net1 up || true

    QEMU_NET_ARGS="-net nic,model=ne2k_pci -net tap,ifname=${TAP_IF},script=no,downscript=no"
    log_success "Macvlan interface net1 attached to $BRIDGE"
  else
    log_warning "net1 interface not found — falling back to socket mode"
    setup_socket_network
  fi
}

# ---------------------------------------------------------------
# MODE: user — QEMU user-mode NAT (isolated, no LAN)
# ---------------------------------------------------------------
setup_user_network() {
  log_info "Setting up user-mode NAT networking (no LAN play)"

  QEMU_NET_ARGS="-netdev user,id=net0,hostfwd=tcp::2300-:2300,hostfwd=udp::2300-:2300,hostfwd=tcp::47624-:47624,hostfwd=udp::47624-:47624 -device ne2k_pci,netdev=net0"

  log_warning "User-mode networking: guests are fully isolated. LAN play disabled."
}

# ---------------------------------------------------------------
# MODE: bridge — Legacy isolated bridge (original)
# ---------------------------------------------------------------
setup_bridge_network() {
  log_info "Setting up legacy isolated bridge network"

  setup_bridge_and_tap

  QEMU_NET_ARGS="-net nic,model=ne2k_pci -net tap,ifname=${TAP_IF},script=no,downscript=no"

  log_warning "Legacy bridge mode: each container is isolated. LAN play disabled."
}

# ---------------------------------------------------------------
# Main dispatcher
# ---------------------------------------------------------------
export QEMU_NET_ARGS=""

case "$NETWORK_MODE" in
  socket)
    setup_socket_network
    ;;
  vxlan)
    setup_vxlan_network
    ;;
  macvlan)
    setup_macvlan_network
    ;;
  user)
    setup_user_network
    ;;
  bridge)
    setup_bridge_network
    ;;
  *)
    log_error "Unknown NETWORK_MODE: $NETWORK_MODE (expected: socket|vxlan|macvlan|user|bridge)"
    exit 1
    ;;
esac

log_success "Network setup complete: mode=$NETWORK_MODE QEMU_NET_ARGS=$QEMU_NET_ARGS"

# Export for use by entrypoint.sh
export NETWORK_MODE GUEST_IP QEMU_NET_ARGS
