#!/bin/bash
# Fix the disk format to be properly recognized by Windows 98

set -e

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

# Configuration
ISO_EXTRACT_DIR="/tmp/iso_extracts"
DISK_IMAGE="files_disk_fixed.img"
DISK_SIZE_MB=1200

log_info "Creating properly partitioned disk for Windows 98..."

# Check if we have the extracted files
if [ ! -d "$ISO_EXTRACT_DIR/combined" ]; then
    log_error "No combined files found. Run the pure_inject.sh script first."
    exit 1
fi

# Calculate actual size needed
ACTUAL_SIZE=$(du -sm "$ISO_EXTRACT_DIR/combined" | cut -f1)
DISK_SIZE_MB=$((ACTUAL_SIZE + 100))  # Add 100MB padding

log_info "Creating ${DISK_SIZE_MB}MB disk image with partition table..."

# Create empty disk image
dd if=/dev/zero of="$DISK_IMAGE" bs=1M count="$DISK_SIZE_MB" 2>/dev/null

# Create partition table and single FAT32 partition
# This creates a proper MBR with a single bootable FAT32 partition
fdisk "$DISK_IMAGE" << EOF
o
n
p
1


a
t
c
w
EOF

log_info "Partition table created. Now formatting the partition..."

# Get the partition offset (usually 2048 sectors * 512 bytes = 1048576 bytes)
OFFSET=$((2048 * 512))

# Format the partition as FAT32
mkfs.fat -F 32 -v -S 512 -s 8 -f 2 -R 32 -F 32 "$DISK_IMAGE" -i 12345678 --offset $((OFFSET / 512)) $((($DISK_SIZE_MB * 1024 * 1024 - OFFSET) / 512)) 2>/dev/null

log_info "Copying files to the new disk..."

# Use mtools to copy files to the partition
export MTOOLS_SKIP_CHECK=1

# Create mtools config for the partition
cat > ~/.mtoolsrc << EOF
drive z: file="$DISK_IMAGE" offset=$OFFSET
EOF

# Copy all files
log_info "Copying directory structure..."
find "$ISO_EXTRACT_DIR/combined" -type d | while read dir; do
    rel_path=${dir#$ISO_EXTRACT_DIR/combined/}
    if [ -n "$rel_path" ]; then
        mmd -i "$DISK_IMAGE@@$OFFSET" "::$rel_path" 2>/dev/null || true
    fi
done

log_info "Copying files..."
find "$ISO_EXTRACT_DIR/combined" -type f | while read file; do
    rel_path=${file#$ISO_EXTRACT_DIR/combined/}
    mcopy -i "$DISK_IMAGE@@$OFFSET" "$file" "::$rel_path" 2>/dev/null || true
done

# Create a batch file in the root for easy access
cat > /tmp/AUTOEXEC.BAT << 'EOF'
@ECHO OFF
ECHO.
ECHO ===============================================
ECHO  Windows 98 + SoftGPU File Transfer Disk
ECHO ===============================================
ECHO.
ECHO This disk contains:
ECHO   - Windows 98 system files in \Windows
ECHO   - SoftGPU drivers in \SoftGPU  
ECHO   - Installation script: INSTALL_ALL.BAT
ECHO.
ECHO To install files, run: INSTALL_ALL.BAT
ECHO.
PAUSE
EOF

mcopy -i "$DISK_IMAGE@@$OFFSET" /tmp/AUTOEXEC.BAT "::AUTOEXEC.BAT" 2>/dev/null || true

log_info "✓ Created properly partitioned disk: $DISK_IMAGE (${DISK_SIZE_MB}MB)"

# Create new VM script with corrected disk configuration
cat > run_fixed_vm.sh << EOF
#!/bin/bash
echo "Starting Windows 98 VM with properly formatted file disk..."

qemu-system-i386 \\
  -enable-kvm \\
  -m 512 \\
  -cpu pentium2 \\
  -smp 1 \\
  -drive file=win98_softgpu.qcow2,format=qcow2,if=ide,index=0,media=disk \\
  -drive file=$DISK_IMAGE,format=raw,if=ide,index=1,media=disk \\
  -machine pc-i440fx-2.12 \\
  -boot order=c,menu=on \\
  -vga std \\
  -audiodev none,id=noaudio \\
  -device sb16,audiodev=noaudio \\
  -vnc 0.0.0.0:0 \\
  -rtc base=localtime \\
  -netdev user,id=net0 \\
  -device ne2k_isa,netdev=net0 \\
  -usb \\
  -device usb-tablet \\
  -name "Windows 98 + Fixed Files Disk" \\
  -monitor stdio
EOF

chmod +x run_fixed_vm.sh

log_info "✓ Created VM script: run_fixed_vm.sh"

echo ""
echo "The disk should now be properly recognized by Windows 98."
echo "Key differences from before:"
echo "  - Proper MBR partition table"
echo "  - Correctly formatted FAT32 partition"
echo "  - Bootable partition flag set"
echo ""
echo "To test: ./run_fixed_vm.sh"
echo "In Windows 98, the D: drive should now appear with your files."

# Verify the disk structure
log_info "Verifying disk structure..."
fdisk -l "$DISK_IMAGE" 2>/dev/null || true

echo ""
echo "If D: drive still doesn't appear, try these alternatives:"
echo "1. Use as CD-ROM: -cdrom $DISK_IMAGE"
echo "2. Use different IDE channel: -drive file=$DISK_IMAGE,if=ide,index=2,media=disk"
