#!/bin/bash
set -euo pipefail

# --- Instance Identity Derivation (K2 contract: POD_NAME via downward API) ---
if [ -n "${POD_NAME:-}" ]; then
  INSTANCE_INDEX=${POD_NAME##*-}
fi
INSTANCE_INDEX=${INSTANCE_INDEX:-0}

BRIDGE=${BRIDGE:-loco-br}
TAP_IF=${TAP_IF:-tap${INSTANCE_INDEX}}

echo "[setup_network] INSTANCE_INDEX=$INSTANCE_INDEX BRIDGE=$BRIDGE TAP_IF=$TAP_IF"

# Create bridge if not exists (idempotent for Kind pods sharing a node)
if ! ip link show "$BRIDGE" &>/dev/null; then
  echo "[setup_network] Creating bridge $BRIDGE"
  ip link add name "$BRIDGE" type bridge
  ip addr add 192.168.10.1/24 dev "$BRIDGE"
  ip link set "$BRIDGE" up
else
  echo "[setup_network] Bridge $BRIDGE already exists"
fi

# Clean up stale TAP if it exists from a previous run
if ip link show "$TAP_IF" &>/dev/null; then
  echo "[setup_network] Removing stale TAP interface $TAP_IF"
  ip link delete "$TAP_IF" || true
fi

# Create TAP device and attach to bridge
echo "[setup_network] Creating TAP interface $TAP_IF"
ip tuntap add "$TAP_IF" mode tap
ip link set "$TAP_IF" up
ip link set "$TAP_IF" master "$BRIDGE"

echo "[setup_network] Network ready: $TAP_IF -> $BRIDGE"
