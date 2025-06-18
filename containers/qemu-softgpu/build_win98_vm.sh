#!/bin/bash
set -e

WIN98_ISO="win98.iso"
LOCO_ZIP="lego_loco.zip"
OUTPUT_IMG="win98_softgpu.qcow2"
SOFTGPU_ISO="softgpu.iso"

DISK_SIZE=2G
RAM_MB=512
CPU_CORES=1

[ -f "$WIN98_ISO" ] || { echo "Missing $WIN98_ISO"; exit 1; }
[ -f "$LOCO_ZIP" ] || { echo "Missing $LOCO_ZIP"; exit 1; }

qemu-img create -f qcow2 "$OUTPUT_IMG" "$DISK_SIZE"

if [ ! -f "$SOFTGPU_ISO" ]; then
  curl -L -o "$SOFTGPU_ISO" https://github.com/JHRobotics/SoftGPU/releases/download/v0.6/softgpu.iso
fi

mkdir -p floppy_data
cp "$LOCO_ZIP" floppy_data/
mkfs.vfat -C floppy.img 1440
mcopy -i floppy.img floppy_data/* ::

echo "Starting QEMU for Windows 98 install..."
qemu-system-i386 \
  -enable-kvm \
  -m "$RAM_MB" \
  -cpu pentium2 \
  -smp "$CPU_CORES" \
  -hda "$OUTPUT_IMG" \
  -cdrom "$WIN98_ISO" \
  -boot d \
  -vga cirrus \
  -soundhw sb16 \
  -fda floppy.img \
  -rtc base=localtime \
  -net nic -net user \
  -name "Win98 Installer" \
  -monitor stdio

echo "After install, shut down manually."
