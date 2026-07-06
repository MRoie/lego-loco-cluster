#!/bin/bash
set -euo pipefail

# --- Instance Identity Derivation (K2 contract: POD_NAME via downward API) ---
if [ -n "${POD_NAME:-}" ]; then
  INSTANCE_INDEX=${POD_NAME##*-}
fi
INSTANCE_INDEX=${INSTANCE_INDEX:-0}
GUEST_MAC=${GUEST_MAC:-52:54:00:10:00:0${INSTANCE_INDEX}}
TAP_IF=${TAP_IF:-tap${INSTANCE_INDEX}}

/usr/local/bin/setup_network.sh

echo "[run-qemu] Starting QEMU with MAC=$GUEST_MAC TAP=$TAP_IF"

qemu-system-i386 \
  -m 1024 \
  -hda /vm/win98_softgpu.qcow2 \
  -drive file=/vm/softgpu.iso,media=cdrom \
  -boot c \
  -net nic,model=ne2k_pci,macaddr=$GUEST_MAC \
  -net tap,ifname=$TAP_IF,script=no,downscript=no \
  -vga vmware \
  -device sb16,audiodev=snd0 \
  -audiodev pa,id=snd0 \
  -vnc :0 &

websockify --web=/usr/share/novnc/ 6080 localhost:5900
