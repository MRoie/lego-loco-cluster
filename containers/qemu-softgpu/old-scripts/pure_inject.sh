#!/bin/bash
# Pure file injection without any mounting or loop devices
# Works in any container environment by manipulating qcow2 directly

set -e

# Configuration
WIN98_ISO="win98.iso"
SOFTGPU_ISO="softgpu.iso"
QCOW2_IMAGE="win98_softgpu.qcow2"
ISO_EXTRACT_DIR="/tmp/iso_extracts"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

show_usage() {
    echo "Pure File Injection (Container-Safe)"
    echo "==================================="
    echo ""
    echo "Usage: $0 [create-fat-disk|embed-iso|combine-images|status]"
    echo ""
    echo "Methods:"
    echo "  create-fat-disk  - Create a FAT disk image with files"
    echo "  embed-iso        - Embed files as ISO in qcow2"
    echo "  combine-images   - Combine qcow2 with data disk"
    echo "  status          - Show current status"
    echo ""
    echo "These methods work without mounting or loop devices"
}

# Check prerequisites
check_prerequisites() {
    for file in "$WIN98_ISO" "$SOFTGPU_ISO" "$QCOW2_IMAGE"; do
        if [ ! -f "$file" ]; then
            log_error "Missing: $file"
            exit 1
        fi
    done
    
    if [ ! -d "$ISO_EXTRACT_DIR" ]; then
        log_info "Extracting ISOs first..."
        extract_isos
    fi
}

# Extract ISOs
extract_isos() {
    if ! command -v 7z &> /dev/null; then
        log_error "7z not found. Install with: sudo apt install p7zip-full"
        exit 1
    fi
    
    rm -rf "$ISO_EXTRACT_DIR"
    mkdir -p "$ISO_EXTRACT_DIR"/{win98,softgpu,combined}
    
    log_info "Extracting Windows 98 ISO..."
    7z x "$WIN98_ISO" -o"$ISO_EXTRACT_DIR/win98" -y > /dev/null 2>&1
    
    log_info "Extracting SoftGPU ISO..."
    7z x "$SOFTGPU_ISO" -o"$ISO_EXTRACT_DIR/softgpu" -y > /dev/null 2>&1
}

# Method 1: Create a FAT disk image that can be attached as second drive
create_fat_disk() {
    log_info "Creating FAT disk image with files..."
    
    check_prerequisites
    
    # Organize files for transfer
    log_info "Organizing files for transfer..."
    rm -rf "$ISO_EXTRACT_DIR/combined"
    mkdir -p "$ISO_EXTRACT_DIR/combined"/{Windows,SoftGPU,Drivers,Tools}
    
    # Copy essential Windows 98 files
    log_info "Selecting essential Windows 98 files..."
    
    # Copy system files
    if [ -d "$ISO_EXTRACT_DIR/win98/WIN98" ]; then
        cp -r "$ISO_EXTRACT_DIR/win98/WIN98"/* "$ISO_EXTRACT_DIR/combined/Windows/" 2>/dev/null || true
    fi
    
    # Copy important executables and drivers
    find "$ISO_EXTRACT_DIR/win98" -name "*.exe" -o -name "*.dll" -o -name "*.sys" -o -name "*.inf" -o -name "*.drv" | while read file; do
        cp "$file" "$ISO_EXTRACT_DIR/combined/Windows/" 2>/dev/null || true
    done
    
    # Copy all SoftGPU files
    log_info "Copying SoftGPU files..."
    cp -r "$ISO_EXTRACT_DIR/softgpu"/* "$ISO_EXTRACT_DIR/combined/SoftGPU/" 2>/dev/null || true
    
    # Create installation scripts
    cat > "$ISO_EXTRACT_DIR/combined/INSTALL_ALL.BAT" << 'EOF'
@ECHO OFF
ECHO.
ECHO ================================================
ECHO  File Installation Script
ECHO ================================================
ECHO.
ECHO Copying Windows system files...
XCOPY D:\Windows C:\Windows /S /E /Y
ECHO.
ECHO Copying SoftGPU drivers...
XCOPY D:\SoftGPU C:\SoftGPU /S /E /Y
ECHO.
ECHO Creating installation shortcuts...
ECHO @ECHO OFF > C:\INSTALL_SOFTGPU.BAT
ECHO CD C:\SoftGPU >> C:\INSTALL_SOFTGPU.BAT
ECHO IF EXIST SETUP.EXE SETUP.EXE >> C:\INSTALL_SOFTGPU.BAT
ECHO IF EXIST INSTALL.EXE INSTALL.EXE >> C:\INSTALL_SOFTGPU.BAT
ECHO.
ECHO Installation complete!
PAUSE
EOF
    
    # Calculate required size
    COMBINED_SIZE=$(du -sm "$ISO_EXTRACT_DIR/combined" | cut -f1)
    DISK_SIZE=$((COMBINED_SIZE + 50))  # Add 50MB padding
    
    log_info "Creating ${DISK_SIZE}MB FAT disk image..."
    
    # Create raw disk image
    FAT_DISK="files_disk.img"
    dd if=/dev/zero of="$FAT_DISK" bs=1M count="$DISK_SIZE" 2>/dev/null
    
    # Format as FAT32 without mounting
    mkfs.fat -F 32 "$FAT_DISK" > /dev/null 2>&1
    
    # Use mtools to copy files without mounting
    if command -v mcopy &> /dev/null; then
        log_info "Using mtools to copy files to FAT disk..."
        
        # Set up mtools config
        export MTOOLS_SKIP_CHECK=1
        
        # Copy files using mtools
        find "$ISO_EXTRACT_DIR/combined" -type f | while read file; do
            rel_path=${file#$ISO_EXTRACT_DIR/combined/}
            mcopy -i "$FAT_DISK" "$file" "::$rel_path" 2>/dev/null || true
        done
        
        log_info "✓ Created $FAT_DISK (${DISK_SIZE}MB)"
        
    else
        log_warn "mtools not available. Installing..."
        sudo apt update && sudo apt install -y mtools
        
        # Retry with mtools
        export MTOOLS_SKIP_CHECK=1
        find "$ISO_EXTRACT_DIR/combined" -type f | while read file; do
            rel_path=${file#$ISO_EXTRACT_DIR/combined/}
            mcopy -i "$FAT_DISK" "$file" "::$rel_path" 2>/dev/null || true
        done
        
        log_info "✓ Created $FAT_DISK (${DISK_SIZE}MB)"
    fi
    
    echo ""
    echo "Created FAT disk image: $FAT_DISK"
    echo "To use this disk:"
    echo "1. Add to your QEMU command: -drive file=$FAT_DISK,if=ide,index=2,media=disk"
    echo "2. In Windows 98, the files will appear on drive D:"
    echo "3. Run D:\\INSTALL_ALL.BAT to copy files to C:"
    
    return 0
}

# Method 2: Embed files as an ISO
embed_iso() {
    log_info "Creating embedded ISO with files..."
    
    check_prerequisites
    
    # Use the existing file_transfer.iso if it exists, or create new one
    if [ ! -f "file_transfer.iso" ]; then
        log_info "Creating new file transfer ISO..."
        
        # Organize files
        rm -rf "$ISO_EXTRACT_DIR/iso_content"
        mkdir -p "$ISO_EXTRACT_DIR/iso_content"/{Windows,SoftGPU,Tools}
        
        # Copy Windows files
        find "$ISO_EXTRACT_DIR/win98" -name "*.exe" -o -name "*.dll" -o -name "*.sys" | head -100 | while read file; do
            cp "$file" "$ISO_EXTRACT_DIR/iso_content/Windows/" 2>/dev/null || true
        done
        
        # Copy SoftGPU files
        cp -r "$ISO_EXTRACT_DIR/softgpu"/* "$ISO_EXTRACT_DIR/iso_content/SoftGPU/" 2>/dev/null || true
        
        # Create autorun and installation files
        cat > "$ISO_EXTRACT_DIR/iso_content/AUTORUN.INF" << 'EOF'
[AUTORUN]
OPEN=INSTALL_ALL.BAT
ICON=SETUP.ICO
LABEL=File Transfer Disk
EOF
        
        cat > "$ISO_EXTRACT_DIR/iso_content/INSTALL_ALL.BAT" << 'EOF'
@ECHO OFF
ECHO Installing files from CD-ROM...
XCOPY D:\Windows C:\Windows /S /E /Y
XCOPY D:\SoftGPU C:\SoftGPU /S /E /Y
ECHO Installation complete!
PAUSE
EOF
        
        # Create ISO
        genisoimage -o file_transfer.iso -R -J -joliet-long -V "TRANSFER" "$ISO_EXTRACT_DIR/iso_content" > /dev/null 2>&1
    fi
    
    log_info "✓ File transfer ISO ready: file_transfer.iso"
    echo ""
    echo "To use this ISO:"
    echo "1. Add to your QEMU command: -cdrom file_transfer.iso"
    echo "2. Or use: -drive file=file_transfer.iso,if=ide,index=2,media=cdrom"
    echo "3. In Windows 98, files will appear on D: drive"
    echo "4. Run D:\\INSTALL_ALL.BAT to install files"
    
    return 0
}

# Method 3: Combine with the main qcow2 image
combine_images() {
    log_info "Combining data with qcow2 image..."
    
    check_prerequisites
    
    # First create the FAT disk if it doesn't exist
    if [ ! -f "files_disk.img" ]; then
        create_fat_disk
    fi
    
    # Convert FAT disk to qcow2
    log_info "Converting FAT disk to qcow2 format..."
    qemu-img convert -f raw -O qcow2 files_disk.img files_disk.qcow2
    
    # Create a script to run both images
    cat > run_combined_vm.sh << 'EOF'
#!/bin/bash
echo "Starting Windows 98 VM with embedded file disk..."

qemu-system-i386 \
  -enable-kvm \
  -m 512 \
  -cpu pentium2 \
  -smp 1 \
  -drive file=win98_softgpu.qcow2,format=qcow2,if=ide,index=0,media=disk \
  -drive file=files_disk.qcow2,format=qcow2,if=ide,index=1,media=disk \
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
  -name "Windows 98 + Files" \
  -monitor stdio
EOF
    
    chmod +x run_combined_vm.sh
    
    log_info "✓ Created combined VM script: run_combined_vm.sh"
    echo ""
    echo "Files are now embedded as a secondary disk in qcow2 format"
    echo "To use: ./run_combined_vm.sh"
    echo "In Windows 98:"
    echo "  - C: = Windows 98 system"
    echo "  - D: = Files disk with installation scripts"
    
    return 0
}

# Show status
show_status() {
    echo "=== Pure Injection Status ==="
    echo ""
    
    # Check source files
    echo "Source files:"
    for file in "$WIN98_ISO" "$SOFTGPU_ISO" "$QCOW2_IMAGE"; do
        if [ -f "$file" ]; then
            echo "  ✓ $file ($(du -h "$file" | cut -f1))"
        else
            echo "  ✗ $file (missing)"
        fi
    done
    
    echo ""
    
    # Check extracted files
    echo "Extracted files:"
    if [ -d "$ISO_EXTRACT_DIR" ]; then
        echo "  ✓ Extraction directory ($(du -sh "$ISO_EXTRACT_DIR" | cut -f1))"
    else
        echo "  ✗ No extracted files"
    fi
    
    echo ""
    
    # Check generated files
    echo "Generated files:"
    for file in "files_disk.img" "files_disk.qcow2" "file_transfer.iso" "run_combined_vm.sh"; do
        if [ -f "$file" ]; then
            echo "  ✓ $file ($(du -h "$file" | cut -f1))"
        else
            echo "  ✗ $file (not created)"
        fi
    done
    
    echo ""
    
    # Check required tools
    echo "Available tools:"
    for tool in "7z" "qemu-img" "genisoimage" "mkfs.fat" "mcopy"; do
        if command -v "$tool" &> /dev/null; then
            echo "  ✓ $tool"
        else
            echo "  ✗ $tool (install with: sudo apt install ${tool})"
        fi
    done
    
    echo ""
    echo "All methods avoid mounting and work in container environments"
}

# Main execution
case "${1:-status}" in
    create-fat-disk)
        create_fat_disk
        ;;
    embed-iso)
        embed_iso
        ;;
    combine-images)
        combine_images
        ;;
    status)
        show_status
        ;;
    *)
        show_usage
        ;;
esac
