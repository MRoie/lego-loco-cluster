#!/bin/bash
set -e

/usr/local/bin/setup_network.sh

qemu-system-i386 \
  -m 512 \
  -hda /vm/win98_softgpu.qcow2 \
  -drive file=/vm/softgpu.iso,media=cdrom \
  -boot c \
  -netdev tap,id=net0,ifname=tap0,script=no,downscript=no \
  -device rtl8139,netdev=net0 \
  -vga std \
  -soundhw sb16 \
  -vnc :0 &

websockify --web=/usr/share/novnc/ 6080 localhost:5900
