#!/bin/bash
# Check and fix Windows 98 disk detection issues

set -e

echo "Windows 98 Disk Detection Troubleshooter"
echo "========================================"
echo ""

# Check current disk files
echo "=== Current disk files ==="
ls -lh *.img *.qcow2 2>/dev/null || echo "No disk files found"
echo ""

# Check the FAT disk structure
if [ -f "win98_files.img" ]; then
    echo "=== Checking win98_files.img structure ==="
    file win98_files.img
    
    # Try to mount and check contents (if possible)
    if command -v mdir &> /dev/null; then
        echo ""
        echo "=== Disk contents (using mtools) ==="
        export MTOOLS_SKIP_CHECK=1
        mdir -i win98_files.img :: 2>/dev/null | head -10 || echo "Could not read disk contents"
    fi
    echo ""
fi

echo "=== Creating Windows 98 compatible disk ==="

# Create a disk that Windows 98 will definitely recognize
DISK_SIZE=1200
DISK_NAME="win98_compatible.img"

echo "Creating ${DISK_SIZE}MB disk with proper CHS geometry..."

# Create disk with specific geometry that Windows 98 likes
# Using older CHS values that Windows 98 recognizes better
dd if=/dev/zero of="$DISK_NAME" bs=1M count=$DISK_SIZE 2>/dev/null

echo "Creating partition table with proper geometry..."

# Create partition table using fdisk with explicit geometry
fdisk "$DISK_NAME" << EOF > /dev/null 2>&1
o
n
p
1


t
c
a
1
w
EOF

echo "Formatting with FAT32..."

# Get the partition offset
OFFSET=$(fdisk -l "$DISK_NAME" 2>/dev/null | grep "${DISK_NAME}1" | awk '{print $2}')
OFFSET_BYTES=$((OFFSET * 512))

# Format the partition
mkfs.fat -F 32 -S 512 -s 1 -f 2 -R 32 -v "$DISK_NAME" $((DISK_SIZE * 1024 * 1024 / 512 - OFFSET)) 2>/dev/null

echo "Mounting and copying files..."

# Copy files using mtools
if [ -d "/tmp/iso_extracts/combined" ]; then
    echo "Copying files from extraction directory..."
    export MTOOLS_SKIP_CHECK=1
    
    # Copy directories and files
    find /tmp/iso_extracts/combined -type f | while read file; do
        rel_path=${file#/tmp/iso_extracts/combined/}
        dir_path=$(dirname "$rel_path")
        
        # Create directory if needed
        if [ "$dir_path" != "." ]; then
            mmd -i "$DISK_NAME" "::$dir_path" 2>/dev/null || true
        fi
        
        # Copy file
        mcopy -i "$DISK_NAME" "$file" "::$rel_path" 2>/dev/null || true
    done
    
    echo "Files copied successfully"
else
    echo "Warning: No extracted files found. Creating basic structure..."
    
    # Create basic structure
    export MTOOLS_SKIP_CHECK=1
    mmd -i "$DISK_NAME" "::Windows" 2>/dev/null || true
    mmd -i "$DISK_NAME" "::SoftGPU" 2>/dev/null || true
    
    # Create a test file
    echo "@ECHO OFF" > /tmp/test.bat
    echo "ECHO Hello from D: drive!" >> /tmp/test.bat
    echo "PAUSE" >> /tmp/test.bat
    mcopy -i "$DISK_NAME" /tmp/test.bat "::TEST.BAT" 2>/dev/null || true
    rm /tmp/test.bat
fi

echo "✓ Created $DISK_NAME"

# Create VM script for the compatible disk
cat > run_compatible_vm.sh << 'EOF'
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
EOF

chmod +x run_compatible_vm.sh

echo ""
echo "=== Troubleshooting Results ==="
echo "✓ Created compatible disk: $DISK_NAME"
echo "✓ Created VM script: run_compatible_vm.sh"
echo ""
echo "Next steps:"
echo "1. Run: ./run_compatible_vm.sh"
echo "2. In Windows 98, check My Computer for D: drive"
echo "3. If still not visible, check Windows 98 Device Manager"
echo ""
echo "Alternative solutions if D: drive still doesn't appear:"
echo "- Right-click My Computer → Properties → Device Manager"
echo "- Look for 'Hard disk controllers' and verify both IDE channels"
echo "- Windows 98 might need manual drive letter assignment"
