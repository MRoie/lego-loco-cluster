#!/bin/bash
echo "Starting Windows 98 VM with compatible disk..."
echo ""
echo "Disk configuration:"
echo "  C: = Windows 98 system (Primary Master)"
echo "  D: = Files disk (Secondary Master)"
echo ""

qemu-system-i386 \
  -enable-kvm \
  -m 512 \
  -cpu pentium2 \
  -smp 1 \
  -hda win98_softgpu.qcow2 \
  -hdb win98_compatible.img \
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
  -name "Windows 98 Compatible" \
  -monitor stdio
