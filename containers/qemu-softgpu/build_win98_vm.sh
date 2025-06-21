#!/bin/bash
set -e

WIN98_ISO="win98.iso"
# LOCO_ZIP="lego_loco.zip"
# OUTPUT_IMG="win98_softgpu.qcow2"
OUTPUT_IMG="../../images/win98.qcow2"


DISK_SIZE=2G
RAM_MB=512
CPU_CORES=1

# [ -f "$WIN98_ISO" ] || { echo "Missing $WIN98_ISO"; exit 1; }
# [ -f "$LOCO_ZIP" ] || { echo "Missing $LOCO_ZIP"; exit 1; }
  # -drive file="$WIN98_ISO",media=cdrom,if=ide,index=1 \
  # -drive file="softgpu.iso",format=raw,if=ide,index=2,media=cdrom,readonly=on \


qemu-system-i386 \
  -enable-kvm \
  -m 768 \
  -cpu pentium3 \
  -smp 1 \
  -bios bios.bin \
  -hda "win98_softgpu.qcow2" \
  -drive file="softgpu.iso",format=raw,if=ide,index=1,media=cdrom,readonly=on \
  -machine pc-i440fx-2.12 \
  -boot order=cd,menu=on \
  -vga std \
  -audiodev none,id=noaudio \
  -device sb16,audiodev=noaudio \
  -vnc 0.0.0.0:0 \
  -rtc base=localtime \
  -netdev user,id=net0 \
  -device ne2k_isa,netdev=net0 \
  -usb \
  -device usb-tablet \
  -name "Win98 Installer with SoftGPU" \
  -monitor stdio

# echo "After install, shut down manually."
