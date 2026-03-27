#!/bin/bash
set -e

BRIDGE=${BRIDGE:-loco-br}
TAP_IF=${TAP_IF:-tap0}

# Create bridge if not exists
if ! ip link show "$BRIDGE" &>/dev/null; then
  ip link add name "$BRIDGE" type bridge
  ip addr add 192.168.10.1/24 dev "$BRIDGE"
  ip link set "$BRIDGE" up
fi

# Create tap device
ip tuntap add "$TAP_IF" mode tap
ip link set "$TAP_IF" up
ip link set "$TAP_IF" master "$BRIDGE"
