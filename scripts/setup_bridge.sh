#!/usr/bin/env bash
# scripts/setup_bridge.sh -- configure shared TAP bridge for emulator containers
set -euo pipefail

BRIDGE=${1:-loco-br}
SUBNET=${2:-192.168.10.0/24}
BRIDGE_ADDR=${3:-192.168.10.1/24}
COUNT=${4:-9}

sudo ip link add name "$BRIDGE" type bridge || true
sudo ip addr add "$BRIDGE_ADDR" dev "$BRIDGE" 2>/dev/null || true
sudo ip link set "$BRIDGE" up

for i in $(seq 0 $((COUNT-1))); do
  IF="tap${i}"
  sudo ip tuntap add "$IF" mode tap 2>/dev/null || true
  sudo ip link set "$IF" master "$BRIDGE"
  sudo ip link set "$IF" up
done

echo "Bridge $BRIDGE with $COUNT TAP interfaces configured"
