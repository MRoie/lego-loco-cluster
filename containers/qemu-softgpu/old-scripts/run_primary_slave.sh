#!/bin/bash
echo "Starting Windows 98 VM with files disk as Primary Slave..."
echo ""
echo "IDE Configuration:"
echo "  Primary Master (C:)   = Windows 98 system"
echo "  Primary Slave  (D:)   = Files disk"
echo ""
echo "This configuration is most compatible with Windows 98"
echo ""

qemu-system-i386 \
  -enable-kvm \
  -m 512 \
  -cpu pentium2 \
  -smp 1 \
  -drive file=win98_softgpu.qcow2,format=qcow2,if=ide,index=0,media=disk \
  -drive file=win98_compatible.img,format=raw,if=ide,index=1,media=disk \
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
  -name "Windows 98 Primary Slave Config" \
  -monitor stdio
