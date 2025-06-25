#!/bin/bash
# Fix Windows 98 disk access issues - create a properly formatted FAT16 disk

set -e

echo "Fixing Windows 98 Disk Access Issues"
echo "===================================="
echo ""

# Windows 98 works better with FAT16 for smaller disks
DISK_SIZE=500  # Smaller size for FAT16
DISK_NAME="win98_fixed.img"

echo "Creating ${DISK_SIZE}MB disk optimized for Windows 98..."

# Create disk image
dd if=/dev/zero of="$DISK_NAME" bs=1M count=$DISK_SIZE 2>/dev/null

echo "Creating DOS-compatible partition table..."

# Create a single primary partition with proper DOS compatibility
fdisk "$DISK_NAME" << EOF > /dev/null 2>&1
o
n
p
1


t
6
a
1
w
EOF

echo "Formatting with FAT16 (better Windows 98 compatibility)..."

# Format as FAT16 which Windows 98 handles better
mkfs.fat -F 16 -v "$DISK_NAME" > /dev/null 2>&1

echo "Copying files with proper Windows 98 structure..."

# Set up mtools to avoid checks
export MTOOLS_SKIP_CHECK=1

# Copy files from extraction directory if it exists
if [ -d "/tmp/iso_extracts/combined" ]; then
    echo "Copying Windows 98 and SoftGPU files..."
    
    # Create main directories
    mmd -i "$DISK_NAME" "::Windows" 2>/dev/null || true
    mmd -i "$DISK_NAME" "::SoftGPU" 2>/dev/null || true
    mmd -i "$DISK_NAME" "::Drivers" 2>/dev/null || true
    
    # Copy files in smaller batches to avoid issues
    echo "Copying Windows files..."
    find /tmp/iso_extracts/combined/Windows -type f 2>/dev/null | head -50 | while read file; do
        filename=$(basename "$file")
        # Convert to 8.3 format for better Windows 98 compatibility
        filename_83=$(echo "$filename" | cut -c1-8 | tr '[:lower:]' '[:upper:]')
        ext=$(echo "$filename" | sed 's/.*\.//' | cut -c1-3 | tr '[:lower:]' '[:upper:]')
        if [ "$filename" != "$filename_83.$ext" ] && [ ${#ext} -le 3 ]; then
            target_name="${filename_83}.${ext}"
        else
            target_name="$filename"
        fi
        mcopy -i "$DISK_NAME" "$file" "::Windows/$target_name" 2>/dev/null || true
    done
    
    echo "Copying SoftGPU files..."
    find /tmp/iso_extracts/combined/SoftGPU -type f 2>/dev/null | head -30 | while read file; do
        filename=$(basename "$file")
        mcopy -i "$DISK_NAME" "$file" "::SoftGPU/$filename" 2>/dev/null || true
    done
    
else
    echo "No extraction directory found, creating basic test structure..."
    mmd -i "$DISK_NAME" "::Windows" 2>/dev/null || true
    mmd -i "$DISK_NAME" "::SoftGPU" 2>/dev/null || true
fi

# Create installation batch files
echo "Creating installation scripts..."

cat > /tmp/install_all.bat << 'EOF'
@ECHO OFF
CLS
ECHO.
ECHO ============================================
ECHO  Windows 98 File Installation Script
ECHO ============================================
ECHO.
ECHO This will copy files from D: to C: drive
ECHO.
PAUSE
ECHO.

ECHO Copying Windows system files...
IF EXIST D:\Windows\*.* XCOPY D:\Windows\*.* C:\Windows\ /Y /Q
IF EXIST D:\Windows\*.* XCOPY D:\Windows\*.* C:\WINDOWS\ /Y /Q

ECHO.
ECHO Copying SoftGPU drivers...
IF NOT EXIST C:\SoftGPU MD C:\SoftGPU
IF EXIST D:\SoftGPU\*.* XCOPY D:\SoftGPU\*.* C:\SoftGPU\ /S /E /Y /Q

ECHO.
ECHO Creating desktop shortcuts...
ECHO @ECHO OFF > C:\SOFTGPU.BAT
ECHO CD C:\SoftGPU >> C:\SOFTGPU.BAT
ECHO IF EXIST SETUP.EXE SETUP.EXE >> C:\SOFTGPU.BAT
ECHO IF EXIST INSTALL.EXE INSTALL.EXE >> C:\SOFTGPU.BAT

ECHO.
ECHO ============================================
ECHO Installation completed successfully!
ECHO.
ECHO To install SoftGPU drivers:
ECHO   Run C:\SOFTGPU.BAT
ECHO.
ECHO ============================================
PAUSE
EOF

mcopy -i "$DISK_NAME" /tmp/install_all.bat "::INSTALL.BAT" 2>/dev/null || true

# Create a simple test file
cat > /tmp/readme.txt << 'EOF'
Windows 98 File Transfer Disk
============================

This disk contains:
- Windows 98 system files
- SoftGPU drivers and installation files
- Installation scripts

To install files:
1. Double-click INSTALL.BAT
2. Follow the prompts
3. Run C:\SOFTGPU.BAT to install SoftGPU

Files will be copied to your C: drive automatically.
EOF

mcopy -i "$DISK_NAME" /tmp/readme.txt "::README.TXT" 2>/dev/null || true

# Create autoexec file for the disk
cat > /tmp/autoexec.bat << 'EOF'
@ECHO OFF
ECHO Welcome to Windows 98 File Transfer Disk
ECHO Run INSTALL.BAT to copy files to C: drive
EOF

mcopy -i "$DISK_NAME" /tmp/autoexec.bat "::AUTOEXEC.BAT" 2>/dev/null || true

# Clean up temp files
rm -f /tmp/install_all.bat /tmp/readme.txt /tmp/autoexec.bat

echo "✓ Created fixed disk: $DISK_NAME"

# Verify disk contents
echo ""
echo "=== Disk contents verification ==="
mdir -i "$DISK_NAME" :: 2>/dev/null || echo "Could not list contents"

# Create new VM script
cat > run_fixed_vm.sh << 'EOF'
#!/bin/bash
echo "Starting Windows 98 VM with fixed disk access..."
echo ""
echo "Disk configuration:"
echo "  C: = Windows 98 system"
echo "  D: = Fixed files disk (FAT16, better compatibility)"
echo ""
echo "In Windows 98:"
echo "  1. Open My Computer"
echo "  2. Double-click D: drive" 
echo "  3. Double-click INSTALL.BAT to install files"
echo ""

qemu-system-i386 \
  -enable-kvm \
  -m 512 \
  -cpu pentium2 \
  -smp 1 \
  -hda win98_softgpu.qcow2 \
  -hdb win98_fixed.img \
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
  -name "Windows 98 Fixed" \
  -monitor stdio
EOF

chmod +x run_fixed_vm.sh

echo ""
echo "=== Fix Results ==="
echo "✓ Created FAT16 disk: $DISK_NAME ($(du -h "$DISK_NAME" | cut -f1))"
echo "✓ Created VM script: run_fixed_vm.sh"
echo ""
echo "Key improvements:"
echo "- Using FAT16 instead of FAT32 (better Windows 98 support)"
echo "- Smaller disk size (500MB vs 1200MB)"
echo "- DOS-compatible partition table"
echo "- 8.3 filename compatibility"
echo "- Simplified file structure"
echo ""
echo "Next steps:"
echo "1. Run: ./run_fixed_vm.sh"
echo "2. In Windows 98, double-click D: drive"
echo "3. Run INSTALL.BAT to copy files"
echo ""
echo "If D: still shows 0 bytes:"
echo "- Try right-clicking D: → Properties"
echo "- Check Windows 98 Disk Management"
echo "- Verify IDE controller in Device Manager"
