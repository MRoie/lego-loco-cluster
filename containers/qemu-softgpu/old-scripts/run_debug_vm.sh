#!/bin/bash
# Windows 98 VM with proper IDE configuration for second drive detection

echo "Starting Windows 98 VM with explicit IDE configuration..."
echo ""
echo "Drive configuration:"
echo "  Primary Master (C:)   = Windows 98 system disk"
echo "  Secondary Master (D:) = Files disk with Windows 98 + SoftGPU files"
echo ""
echo "VNC access: localhost:5900"
echo ""

qemu-system-i386 \
  -enable-kvm \
  -m 512 \
  -cpu pentium2 \
  -smp 1 \
  -drive file=win98_softgpu.qcow2,format=qcow2,if=ide,bus=0,unit=0,media=disk \
  -drive file=win98_files.img,format=raw,if=ide,bus=1,unit=0,media=disk \
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
  -name "Windows 98 Debug" \
  -monitor stdio

echo ""
echo "If drive D: still doesn't appear:"
echo "1. Check Device Manager in Windows 98"
echo "2. Try running Windows 98 disk management tools"
echo "3. The disk might need to be assigned a drive letter manually"
