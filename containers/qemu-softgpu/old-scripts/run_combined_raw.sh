#!/bin/bash
echo "Starting Windows 98 VM with RAW file disk (better compatibility)..."

qemu-system-i386 \
  -enable-kvm \
  -m 512 \
  -cpu pentium2 \
  -smp 1 \
  -hda win98_softgpu.qcow2 \
  -hdb files_disk.img \
  -machine pc-i440fx-2.12 \
  -boot order=c,menu=on \
  -vga std \
  -audiodev none,id=noaudio \
  -device sb16,audiodev=noaudio \
  -vnc 0.0.0.0:0 \
  -rtc base=localtime \
  -netdev user,id=net0 \
  -device ne2k_isa,netdev=net0 \
  -usb \
  -device usb-tablet \
  -name "Windows 98 + Files (RAW)" \
  -monitor stdio
