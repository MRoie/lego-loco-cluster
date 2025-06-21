#!/bin/bash
# Alternative file injection method using qemu-nbd (no loop devices needed)
# This method works better in container environments

set -e

# Configuration
WIN98_ISO="win98.iso"
SOFTGPU_ISO="softgpu.iso"
QCOW2_IMAGE="win98_softgpu.qcow2"
MOUNT_POINT="/tmp/win98_mount"
ISO_EXTRACT_DIR="/tmp/iso_extracts"
NBD_DEVICE="/dev/nbd0"

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
    echo "Usage: $0 [inject|status|clean]"
    echo ""
    echo "This is the NBD-based alternative injection method"
    echo "Commands:"
    echo "  inject   - Inject extracted files into qcow2 image using NBD"
    echo "  status   - Show current status"
    echo "  clean    - Clean up NBD connections and mounts"
}

# Cleanup function
cleanup_nbd() {
    log_info "Cleaning up NBD connections..."
    
    # Unmount if mounted
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        sudo umount "$MOUNT_POINT" || true
    fi
    
    # Disconnect NBD
    if [ -b "$NBD_DEVICE" ]; then
        sudo qemu-nbd --disconnect "$NBD_DEVICE" 2>/dev/null || true
    fi
    
    log_info "✓ Cleanup completed"
}

# Check if we can use NBD
check_nbd() {
    if ! command -v qemu-nbd &> /dev/null; then
        log_error "qemu-nbd not found. Install with: sudo apt install qemu-utils"
        exit 1
    fi
    
    # Check if NBD module is loaded (this might not work in containers)
    if ! lsmod | grep -q nbd 2>/dev/null; then
        log_warn "NBD module not loaded. Trying to load..."
        sudo modprobe nbd max_part=8 2>/dev/null || {
            log_warn "Cannot load NBD module (normal in containers)"
        }
    fi
}

# Inject files using NBD
inject_with_nbd() {
    log_info "Injecting files using qemu-nbd method..."
    
    if [ ! -d "$ISO_EXTRACT_DIR" ]; then
        log_error "No extracted files found. Run './inject_files.sh extract' first."
        exit 1
    fi
    
    check_nbd
    
    # Cleanup any existing connections
    cleanup_nbd
    
    # Connect qcow2 image via NBD
    log_info "Connecting qcow2 image via NBD..."
    sudo qemu-nbd --connect="$NBD_DEVICE" "$QCOW2_IMAGE" || {
        log_error "Failed to connect via NBD. Trying alternative method..."
        inject_alternative
        return
    }
    
    # Wait for device to be ready
    sleep 3
    
    # Check partitions
    log_info "Checking partitions..."
    sudo fdisk -l "$NBD_DEVICE" 2>/dev/null || true
    
    # Create mount point
    sudo mkdir -p "$MOUNT_POINT"
    
    # Try to mount the first partition
    log_info "Mounting Windows partition..."
    local partition="${NBD_DEVICE}p1"
    
    if [ ! -b "$partition" ]; then
        log_warn "Partition $partition not found, trying whole device..."
        partition="$NBD_DEVICE"
    fi
    
    if sudo mount -t ntfs-3g "$partition" "$MOUNT_POINT" 2>/dev/null; then
        log_info "✓ Mounted as NTFS"
    elif sudo mount -t vfat "$partition" "$MOUNT_POINT" 2>/dev/null; then
        log_info "✓ Mounted as FAT"
    elif sudo mount "$partition" "$MOUNT_POINT" 2>/dev/null; then
        log_info "✓ Mounted (auto-detected)"
    else
        log_error "Failed to mount partition. Image might not be formatted or partitioned."
        cleanup_nbd
        exit 1
    fi
    
    # Now copy files
    copy_files_to_mount
    
    # Cleanup
    cleanup_nbd
    
    log_info "✓ File injection completed successfully using NBD!"
}

# Alternative method without NBD
inject_alternative() {
    log_info "Using alternative method: mounting via direct file access..."
    
    # Check if we can use guestmount (if available)
    if command -v guestmount &> /dev/null; then
        log_info "Using guestmount method..."
        sudo mkdir -p "$MOUNT_POINT"
        
        if guestmount -a "$QCOW2_IMAGE" -m /dev/sda1 "$MOUNT_POINT" 2>/dev/null; then
            log_info "✓ Mounted with guestmount"
            copy_files_to_mount
            fusermount -u "$MOUNT_POINT" || sudo umount "$MOUNT_POINT"
            return
        fi
    fi
    
    log_error "All mounting methods failed. The qcow2 image might need to be:"
    log_error "1. Properly partitioned"
    log_error "2. Formatted with a supported filesystem (FAT32/NTFS)"
    log_error "3. Have Windows 98 installed first"
    echo ""
    echo "You may need to:"
    echo "1. Boot the VM and install Windows 98 first"
    echo "2. Or create a properly formatted image"
}

# Copy files to mounted filesystem
copy_files_to_mount() {
    log_info "Copying files to mounted filesystem..."
    
    # Show current contents
    log_info "Current contents of mounted image:"
    sudo ls -la "$MOUNT_POINT" | head -5
    
    # Create Windows directory structure
    log_info "Creating Windows directory structure..."
    sudo mkdir -p "$MOUNT_POINT"/{Windows,WINDOWS}/{System,System32,Desktop,Temp,Fonts,Help,Media,Web}
    sudo mkdir -p "$MOUNT_POINT"/{Program\ Files,PROGRA~1}
    sudo mkdir -p "$MOUNT_POINT"/Drivers/{Display,Audio,Network}
    sudo mkdir -p "$MOUNT_POINT"/Games
    sudo mkdir -p "$MOUNT_POINT"/Temp
    sudo mkdir -p "$MOUNT_POINT"/SOFTGPU
    
    # Copy Windows 98 system files
    log_info "Copying Windows 98 system files..."
    if [ -d "$ISO_EXTRACT_DIR/win98/WIN98" ]; then
        sudo cp -r "$ISO_EXTRACT_DIR/win98/WIN98"/* "$MOUNT_POINT/WINDOWS/" 2>/dev/null || true
    fi
    
    # Copy Windows 98 installation files
    if [ -d "$ISO_EXTRACT_DIR/win98" ]; then
        # Copy important Windows files
        for ext in EXE DLL SYS INF CAB MSI; do
            find "$ISO_EXTRACT_DIR/win98" -name "*.$ext" -o -name "*.${ext,,}" | while read -r file; do
                if [ -f "$file" ]; then
                    sudo cp "$file" "$MOUNT_POINT/WINDOWS/" 2>/dev/null || true
                fi
            done
        done
    fi
    
    # Copy SoftGPU drivers
    log_info "Copying SoftGPU drivers..."
    if [ -d "$ISO_EXTRACT_DIR/softgpu" ]; then
        sudo cp -r "$ISO_EXTRACT_DIR/softgpu"/* "$MOUNT_POINT/Drivers/Display/" 2>/dev/null || true
        sudo cp -r "$ISO_EXTRACT_DIR/softgpu"/* "$MOUNT_POINT/SOFTGPU/" 2>/dev/null || true
    fi
    
    # Create installation batch files
    log_info "Creating installation batch files..."
    
    sudo tee "$MOUNT_POINT/INSTALL_SOFTGPU.BAT" > /dev/null << 'EOF'
@ECHO OFF
ECHO Installing SoftGPU drivers...
CD C:\SOFTGPU
IF EXIST SETUP.EXE SETUP.EXE
IF EXIST INSTALL.EXE INSTALL.EXE
IF EXIST SOFTGPU.EXE SOFTGPU.EXE
ECHO SoftGPU installation complete.
PAUSE
EOF
    
    sudo tee "$MOUNT_POINT/README.TXT" > /dev/null << 'EOF'
This Windows 98 image has been pre-populated with:

1. Windows 98 system files in C:\WINDOWS\
2. SoftGPU drivers in C:\SOFTGPU\ and C:\Drivers\Display\

To install SoftGPU:
- Run C:\INSTALL_SOFTGPU.BAT
- Or manually run the installer from C:\SOFTGPU\

Files were injected automatically to save installation time.
EOF
    
    # Create autoexec.bat and config.sys
    if [ ! -f "$MOUNT_POINT/AUTOEXEC.BAT" ]; then
        sudo tee "$MOUNT_POINT/AUTOEXEC.BAT" > /dev/null << 'EOF'
@ECHO OFF
PATH C:\WINDOWS;C:\WINDOWS\COMMAND;C:\
SET TEMP=C:\TEMP
SET TMP=C:\TEMP
ECHO Windows 98 with SoftGPU - Ready to use!
EOF
    fi
    
    if [ ! -f "$MOUNT_POINT/CONFIG.SYS" ]; then
        sudo tee "$MOUNT_POINT/CONFIG.SYS" > /dev/null << 'EOF'
DOS=HIGH,UMB
FILES=30
BUFFERS=20
DEVICE=C:\WINDOWS\HIMEM.SYS
DEVICE=C:\WINDOWS\EMM386.EXE NOEMS
EOF
    fi
    
    # Show final result
    log_info "Files copied successfully!"
    log_info "Final directory structure:"
    sudo ls -la "$MOUNT_POINT" | head -10
    
    # Calculate space used
    local space_used=$(sudo du -sh "$MOUNT_POINT" 2>/dev/null | cut -f1 || echo "unknown")
    log_info "Total space used: $space_used"
}

# Show status
show_status() {
    echo "=== NBD Injection Status ==="
    echo ""
    
    # Check qcow2 image
    if [ -f "$QCOW2_IMAGE" ]; then
        echo "  ✓ $QCOW2_IMAGE ($(du -h "$QCOW2_IMAGE" | cut -f1))"
    else
        echo "  ✗ $QCOW2_IMAGE (missing)"
    fi
    
    # Check extracted files
    if [ -d "$ISO_EXTRACT_DIR" ]; then
        echo "  ✓ Extracted files available ($(du -sh "$ISO_EXTRACT_DIR" | cut -f1))"
    else
        echo "  ✗ No extracted files (run './inject_files.sh extract' first)"
    fi
    
    # Check NBD status
    if [ -b "$NBD_DEVICE" ]; then
        echo "  ✓ NBD device available"
        if sudo qemu-nbd --list 2>/dev/null | grep -q "$NBD_DEVICE"; then
            echo "  ⚠ NBD device is currently in use"
        fi
    else
        echo "  ✗ NBD device not available"
    fi
    
    # Check mount status
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        echo "  ⚠ Image is currently mounted at $MOUNT_POINT"
    else
        echo "  ✓ No active mounts"
    fi
}

# Main command handling
case "${1:-}" in
    inject)
        inject_with_nbd
        ;;
    status)
        show_status
        ;;
    clean)
        cleanup_nbd
        ;;
    *)
        show_usage
        exit 1
        ;;
esac
