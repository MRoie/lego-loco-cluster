#!/bin/bash
# Simple disk creation that Windows 98 will definitely recognize

set -e

# Configuration
DISK_NAME="win98_files.img"
DISK_SIZE_MB=1200
COMBINED_DIR="/tmp/iso_extracts/combined"

echo "[INFO] Creating simple FAT32 disk for Windows 98..."

# Remove old disk
rm -f "$DISK_NAME"

# Create disk image
echo "[INFO] Creating ${DISK_SIZE_MB}MB disk image..."
dd if=/dev/zero of="$DISK_NAME" bs=1M count="$DISK_SIZE_MB" status=progress

# Format as FAT32 (simple approach)
echo "[INFO] Formatting as FAT32..."
mkfs.fat -F 32 "$DISK_NAME"

# Copy files using mtools (no mounting required)
if [ -d "$COMBINED_DIR" ]; then
    echo "[INFO] Copying files to disk using mtools..."
    
    export MTOOLS_SKIP_CHECK=1
    
    # Copy directories
    if [ -d "$COMBINED_DIR/Windows" ]; then
        echo "Copying Windows files..."
        mcopy -s -i "$DISK_NAME" "$COMBINED_DIR/Windows" "::/"
    fi
    
    if [ -d "$COMBINED_DIR/SoftGPU" ]; then
        echo "Copying SoftGPU files..."
        mcopy -s -i "$DISK_NAME" "$COMBINED_DIR/SoftGPU" "::/"
    fi
    
    # Copy batch files
    if [ -f "$COMBINED_DIR/INSTALL_ALL.BAT" ]; then
        echo "Copying installation scripts..."
        mcopy -i "$DISK_NAME" "$COMBINED_DIR/INSTALL_ALL.BAT" "::/"
    fi
    
    echo "[INFO] ✓ Created $DISK_NAME with files"
else
    echo "[WARN] No combined directory found, creating empty disk"
fi

# Create updated VM script
cat > run_files_vm.sh << 'EOF'
#!/bin/bash
echo "Starting Windows 98 VM with files disk..."

qemu-system-i386 \
  -enable-kvm \
  -m 512 \
  -cpu pentium2 \
  -smp 1 \
  -drive file=win98_softgpu.qcow2,format=qcow2,if=ide,index=0,media=disk \
  -drive file=win98_files.img,format=raw,if=ide,index=1,media=disk \
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
  -name "Windows 98 + Files Disk" \
  -monitor stdio
EOF

chmod +x run_files_vm.sh

echo ""
echo "✓ Created simple FAT32 disk: $DISK_NAME"
echo "✓ Created VM script: run_files_vm.sh"
echo ""
echo "To test:"
echo "  ./run_files_vm.sh"
echo ""
echo "In Windows 98, drive D: should now appear with your files"
echo "Run D:\\INSTALL_ALL.BAT to copy files to C: drive"
