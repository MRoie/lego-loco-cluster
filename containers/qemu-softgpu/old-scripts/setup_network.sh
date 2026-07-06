#!/bin/bash
set -e

# Create bridge if not exists
if ! ip link show br0 &>/dev/null; then
  brctl addbr br0
  ip link set dev br0 up
fi

# Create tap device
ip tuntap add tap0 mode tap user root
ip link set tap0 up
ip link set tap0 master br0
