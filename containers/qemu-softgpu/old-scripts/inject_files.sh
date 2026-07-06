#!/bin/bash
# Pre-populate Windows 98 qcow2 image with files from ISOs
# This bypasses the slow Windows 98 installation and file copying

set -e

# Configuration
WIN98_ISO="win98.iso"
SOFTGPU_ISO="softgpu.iso"
QCOW2_IMAGE="win98_softgpu.qcow2"
RAW_IMAGE="win98_temp.raw"
MOUNT_POINT="/tmp/win98_mount"
ISO_EXTRACT_DIR="/tmp/iso_extracts"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_usage() {
    echo "Usage: $0 [extract|inject|full|clean|status]"
    echo ""
    echo "Commands:"
    echo "  extract  - Extract files from ISOs to staging area"
    echo "  inject   - Inject extracted files into qcow2 image"
    echo "  full     - Do complete extraction and injection"
    echo "  clean    - Clean up temporary files"
    echo "  status   - Show current status"
    echo ""
    echo "Files needed:"
    echo "  - $WIN98_ISO (Windows 98 installation ISO)"
    echo "  - $SOFTGPU_ISO (SoftGPU drivers ISO)"
    echo "  - $QCOW2_IMAGE (Windows 98 qcow2 image - must be formatted)"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing=0
    
    if [ ! -f "$WIN98_ISO" ]; then
        log_error "Missing: $WIN98_ISO"
        missing=1
    fi
    
    if [ ! -f "$SOFTGPU_ISO" ]; then
        log_error "Missing: $SOFTGPU_ISO"
        missing=1
    fi
    
    if [ ! -f "$QCOW2_IMAGE" ]; then
        log_error "Missing: $QCOW2_IMAGE"
        missing=1
    fi
    
    # Check for required tools
    for tool in 7z qemu-img losetup; do
        if ! command -v $tool &> /dev/null; then
            log_error "Missing tool: $tool"
            missing=1
        fi
    done
    
    if [ $missing -eq 1 ]; then
        log_error "Prerequisites not met. Install missing tools with:"
        echo "  sudo apt update && sudo apt install -y p7zip-full qemu-utils"
        exit 1
    fi
    
    log_info "✓ All prerequisites met"
}

# Extract files from ISOs
extract_isos() {
    log_info "Extracting files from ISOs..."
    
    # Clean and create extraction directory
    rm -rf "$ISO_EXTRACT_DIR"
    mkdir -p "$ISO_EXTRACT_DIR"/{win98,softgpu}
    
    # Extract Windows 98 ISO
    log_info "Extracting Windows 98 files..."
    7z x "$WIN98_ISO" -o"$ISO_EXTRACT_DIR/win98" -y > /dev/null 2>&1
    
    # Extract SoftGPU ISO
    log_info "Extracting SoftGPU files..."
    7z x "$SOFTGPU_ISO" -o"$ISO_EXTRACT_DIR/softgpu" -y > /dev/null 2>&1
    
    # Show what we extracted
    log_info "Extracted contents:"
    echo "Windows 98 files:"
    ls -la "$ISO_EXTRACT_DIR/win98" | head -5
    echo "..."
    echo ""
    echo "SoftGPU files:"
    ls -la "$ISO_EXTRACT_DIR/softgpu" | head -5
    echo "..."
    
    # Calculate total size
    local total_size=$(du -sh "$ISO_EXTRACT_DIR" | cut -f1)
    log_info "Total extracted size: $total_size"
}

# Create directory structure for Windows 98
create_windows_structure() {
    local target_dir="$1"
    
    log_info "Creating Windows directory structure..."
    
    # Create typical Windows 98 directories
    sudo mkdir -p "$target_dir"/{Windows,WINDOWS}/{System,System32,Desktop,Temp,Fonts,Help,Media,Web}
    sudo mkdir -p "$target_dir"/{Program\ Files,PROGRA~1}
    sudo mkdir -p "$target_dir"/Drivers/{Display,Audio,Network}
    sudo mkdir -p "$target_dir"/Games
    sudo mkdir -p "$target_dir"/Temp
    
    # Create autoexec.bat and config.sys if they don't exist
    if [ ! -f "$target_dir/AUTOEXEC.BAT" ]; then
        sudo tee "$target_dir/AUTOEXEC.BAT" > /dev/null << 'EOF'
@ECHO OFF
PATH C:\WINDOWS;C:\WINDOWS\COMMAND;C:\
SET TEMP=C:\TEMP
SET TMP=C:\TEMP
EOF
    fi
    
    if [ ! -f "$target_dir/CONFIG.SYS" ]; then
        sudo tee "$target_dir/CONFIG.SYS" > /dev/null << 'EOF'
DOS=HIGH,UMB
FILES=30
BUFFERS=20
DEVICE=C:\WINDOWS\HIMEM.SYS
DEVICE=C:\WINDOWS\EMM386.EXE NOEMS
EOF
    fi
}

# Inject files into qcow2 image
inject_files() {
    log_info "Injecting files into qcow2 image..."
    
    if [ ! -d "$ISO_EXTRACT_DIR" ]; then
        log_error "No extracted files found. Run 'extract' first."
        exit 1
    fi
    
    # Convert qcow2 to raw for mounting
    log_info "Converting qcow2 to raw format..."
    qemu-img convert -f qcow2 -O raw "$QCOW2_IMAGE" "$RAW_IMAGE"
    
    # Find or create available loop device
    local loop_device
    
    # Try to find an existing free loop device
    for i in {0..7}; do
        if [ -b "/dev/loop$i" ] && ! losetup -a | grep -q "/dev/loop$i"; then
            loop_device="/dev/loop$i"
            break
        fi
    done
    
    # If no existing device found, try to create one
    if [ -z "$loop_device" ]; then
        for i in {0..15}; do
            if [ ! -b "/dev/loop$i" ]; then
                log_info "Creating loop device /dev/loop$i"
                sudo mknod "/dev/loop$i" b 7 "$i" 2>/dev/null || true
                if [ -b "/dev/loop$i" ]; then
                    loop_device="/dev/loop$i"
                    break
                fi
            fi
        done
    fi
    
    # Use losetup to find a free device automatically as fallback
    if [ -z "$loop_device" ]; then
        log_info "Using losetup to find free device automatically"
        loop_device=$(sudo losetup -f 2>/dev/null || echo "")
    fi
    
    if [ -z "$loop_device" ]; then
        log_error "No available loop devices found and cannot create new ones"
        log_error "Try running: sudo modprobe loop max_loop=16"
        exit 1
    fi
    
    log_info "Using loop device: $loop_device"
    
    # Setup loop device
    sudo losetup "$loop_device" "$RAW_IMAGE"
    
    # Wait for device to be ready
    sleep 2
    
    # Create mount point
    sudo mkdir -p "$MOUNT_POINT"
    
    # Try to mount (assuming first partition is Windows)
    log_info "Mounting Windows partition..."
    if sudo mount -t ntfs-3g "${loop_device}p1" "$MOUNT_POINT" 2>/dev/null; then
        log_info "✓ Mounted as NTFS"
    elif sudo mount -t vfat "${loop_device}p1" "$MOUNT_POINT" 2>/dev/null; then
        log_info "✓ Mounted as FAT"
    elif sudo mount "${loop_device}p1" "$MOUNT_POINT" 2>/dev/null; then
        log_info "✓ Mounted (auto-detected)"
    else
        log_error "Failed to mount partition. Is the image formatted?"
        cleanup_loop "$loop_device"
        exit 1
    fi
    
    # Create Windows directory structure
    create_windows_structure "$MOUNT_POINT"
    
    # Copy Windows 98 system files
    log_info "Copying Windows 98 system files..."
    if [ -d "$ISO_EXTRACT_DIR/win98/WIN98" ]; then
        sudo cp -r "$ISO_EXTRACT_DIR/win98/WIN98"/* "$MOUNT_POINT/WINDOWS/" 2>/dev/null || true
    fi
    
    # Copy essential Windows files
    for ext in EXE DLL SYS INF CAB; do
        for file in "$ISO_EXTRACT_DIR/win98"/*."$ext" "$ISO_EXTRACT_DIR/win98"/*."${ext,,}"; do
            if [ -f "$file" ]; then
                sudo cp "$file" "$MOUNT_POINT/WINDOWS/" 2>/dev/null || true
            fi
        done
    done
    
    # Copy SoftGPU drivers
    log_info "Copying SoftGPU drivers..."
    sudo cp -r "$ISO_EXTRACT_DIR/softgpu"/* "$MOUNT_POINT/Drivers/Display/" 2>/dev/null || true
    
    # Create installation batch file for SoftGPU
    sudo tee "$MOUNT_POINT/INSTALL_SOFTGPU.BAT" > /dev/null << 'EOF'
@ECHO OFF
ECHO Installing SoftGPU drivers...
CD C:\Drivers\Display
IF EXIST SETUP.EXE SETUP.EXE
IF EXIST INSTALL.EXE INSTALL.EXE
ECHO SoftGPU installation complete.
PAUSE
EOF
    
    # Copy drivers to a more accessible location
    sudo mkdir -p "$MOUNT_POINT/SOFTGPU"
    sudo cp -r "$ISO_EXTRACT_DIR/softgpu"/* "$MOUNT_POINT/SOFTGPU/" 2>/dev/null || true
    
    log_info "File injection completed successfully!"
    
    # Show what was copied
    log_info "Files in C: drive:"
    sudo ls -la "$MOUNT_POINT" | head -10
    
    # Cleanup
    cleanup_loop "$loop_device"
}

# Cleanup function
cleanup_loop() {
    local loop_device="$1"
    
    log_info "Cleaning up..."
    
    # Unmount if mounted
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        sudo umount "$MOUNT_POINT"
    fi
    
    # Detach loop device
    if [ -n "$loop_device" ] && [ -b "$loop_device" ]; then
        sudo losetup -d "$loop_device"
    fi
    
    # Convert raw back to qcow2
    if [ -f "$RAW_IMAGE" ]; then
        log_info "Converting back to qcow2..."
        qemu-img convert -f raw -O qcow2 "$RAW_IMAGE" "$QCOW2_IMAGE"
        rm -f "$RAW_IMAGE"
    fi
    
    log_info "✓ Cleanup completed"
}

# Clean all temporary files
clean_all() {
    log_info "Cleaning all temporary files..."
    
    # Cleanup any active mounts
    cleanup_loop ""
    
    # Remove extraction directory
    rm -rf "$ISO_EXTRACT_DIR"
    
    # Remove temporary files
    rm -f "$RAW_IMAGE"
    
    log_info "✓ All temporary files cleaned"
}

# Show current status
show_status() {
    echo "=== File Injection Status ==="
    echo ""
    
    # Check ISOs
    echo "Source ISOs:"
    for iso in "$WIN98_ISO" "$SOFTGPU_ISO"; do
        if [ -f "$iso" ]; then
            echo "  ✓ $iso ($(du -h "$iso" | cut -f1))"
        else
            echo "  ✗ $iso (missing)"
        fi
    done
    
    echo ""
    
    # Check qcow2 image
    echo "Target image:"
    if [ -f "$QCOW2_IMAGE" ]; then
        echo "  ✓ $QCOW2_IMAGE ($(du -h "$QCOW2_IMAGE" | cut -f1))"
    else
        echo "  ✗ $QCOW2_IMAGE (missing)"
    fi
    
    echo ""
    
    # Check extracted files
    echo "Extracted files:"
    if [ -d "$ISO_EXTRACT_DIR" ]; then
        echo "  ✓ Extraction directory exists ($(du -sh "$ISO_EXTRACT_DIR" | cut -f1))"
        echo "    - Windows 98: $(ls "$ISO_EXTRACT_DIR/win98" 2>/dev/null | wc -l) files"
        echo "    - SoftGPU: $(ls "$ISO_EXTRACT_DIR/softgpu" 2>/dev/null | wc -l) files"
    else
        echo "  ✗ No extracted files found"
    fi
    
    echo ""
    
    # Check tools
    echo "Required tools:"
    for tool in 7z qemu-img losetup; do
        if command -v $tool &> /dev/null; then
            echo "  ✓ $tool"
        else
            echo "  ✗ $tool (missing)"
        fi
    done
}

# Main command handling
case "${1:-}" in
    extract)
        check_prerequisites
        extract_isos
        ;;
    inject)
        check_prerequisites
        inject_files
        ;;
    full)
        check_prerequisites
        extract_isos
        inject_files
        ;;
    clean)
        clean_all
        ;;
    status)
        show_status
        ;;
    *)
        show_usage
        exit 1
        ;;
esac
