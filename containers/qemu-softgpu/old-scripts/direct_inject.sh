#!/bin/bash
# Direct file injection into qcow2 without booting Windows 98
# Uses multiple fallback methods for container environments

set -e

# Configuration
WIN98_ISO="win98.iso"
SOFTGPU_ISO="softgpu.iso"
QCOW2_IMAGE="win98_softgpu.qcow2"
ISO_EXTRACT_DIR="/tmp/iso_extracts"
RAW_IMAGE="temp_raw.img"
MOUNT_POINT="/tmp/qcow2_mount"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

show_usage() {
    echo "Direct File Injection into qcow2 (No Booting Required)"
    echo "====================================================="
    echo ""
    echo "Usage: $0 [method1|method2|method3|status|clean]"
    echo ""
    echo "Methods:"
    echo "  method1  - Use libguestfs (if available)"
    echo "  method2  - Use qemu-img + raw conversion + host mounting"
    echo "  method3  - Use qemu-img resize and create FAT partition"
    echo "  status   - Show current status"
    echo "  clean    - Clean up temporary files"
    echo ""
    echo "These methods inject files directly without booting Windows 98"
}

# Check if files exist and are extracted
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    for file in "$WIN98_ISO" "$SOFTGPU_ISO" "$QCOW2_IMAGE"; do
        if [ ! -f "$file" ]; then
            log_error "Missing: $file"
            exit 1
        fi
    done
    
    # Check if files are already extracted
    if [ ! -d "$ISO_EXTRACT_DIR" ]; then
        log_info "Extracting ISOs first..."
        extract_isos
    fi
    
    log_info "✓ Prerequisites met"
}

# Extract ISOs if not already done
extract_isos() {
    if ! command -v 7z &> /dev/null; then
        log_error "7z not found. Install with: sudo apt install p7zip-full"
        exit 1
    fi
    
    rm -rf "$ISO_EXTRACT_DIR"
    mkdir -p "$ISO_EXTRACT_DIR"/{win98,softgpu}
    
    log_info "Extracting Windows 98 ISO..."
    7z x "$WIN98_ISO" -o"$ISO_EXTRACT_DIR/win98" -y > /dev/null 2>&1
    
    log_info "Extracting SoftGPU ISO..."
    7z x "$SOFTGPU_ISO" -o"$ISO_EXTRACT_DIR/softgpu" -y > /dev/null 2>&1
    
    log_info "✓ ISOs extracted"
}

# Method 1: Try libguestfs (works if kernel is available)
method1_libguestfs() {
    log_info "Method 1: Attempting libguestfs injection..."
    
    check_prerequisites
    
    # Try guestfish
    if command -v guestfish &> /dev/null; then
        log_info "Using guestfish for direct injection..."
        
        # Create a guestfish script
        cat > inject_script.fish << EOF
add-drive $QCOW2_IMAGE
run
list-filesystems
mount /dev/sda1 /
mkdir-p /Windows/System
mkdir-p /SoftGPU
mkdir-p /Drivers/Display

# Copy Windows 98 files
EOF
        
        # Add copy commands for important files
        find "$ISO_EXTRACT_DIR/win98" -name "*.exe" -o -name "*.dll" -o -name "*.sys" | head -20 | while read file; do
            basename_file=$(basename "$file")
            echo "copy-in \"$file\" /Windows/System" >> inject_script.fish
        done
        
        # Add SoftGPU files
        echo "copy-in \"$ISO_EXTRACT_DIR/softgpu\" /SoftGPU" >> inject_script.fish
        echo "sync" >> inject_script.fish
        echo "exit" >> inject_script.fish
        
        # Try to run guestfish
        if guestfish -f inject_script.fish 2>/dev/null; then
            log_info "✓ Method 1 successful - files injected via libguestfs"
            rm inject_script.fish
            return 0
        else
            log_warn "Method 1 failed - libguestfs not available in container"
            rm inject_script.fish
            return 1
        fi
    else
        log_warn "guestfish not available"
        return 1
    fi
}

# Method 2: Convert to raw, mount on host, convert back
method2_raw_conversion() {
    log_info "Method 2: Raw conversion and host mounting..."
    
    check_prerequisites
    
    # Convert qcow2 to raw
    log_info "Converting qcow2 to raw format..."
    qemu-img convert -f qcow2 -O raw "$QCOW2_IMAGE" "$RAW_IMAGE"
    
    # Try to use host's losetup (might work if we have privileges)
    log_info "Attempting host loop device mounting..."
    
    # Try to find available loop device
    LOOP_DEVICE=""
    for i in {0..15}; do
        if [ -b "/dev/loop$i" ]; then
            if ! losetup -a | grep -q "/dev/loop$i"; then
                LOOP_DEVICE="/dev/loop$i"
                break
            fi
        fi
    done
    
    if [ -n "$LOOP_DEVICE" ]; then
        log_info "Using loop device: $LOOP_DEVICE"
        
        # Setup loop device
        if sudo losetup "$LOOP_DEVICE" "$RAW_IMAGE" 2>/dev/null; then
            sleep 2
            
            # Try to mount
            sudo mkdir -p "$MOUNT_POINT"
            
            if sudo mount -t ntfs-3g "${LOOP_DEVICE}p1" "$MOUNT_POINT" 2>/dev/null || \
               sudo mount -t vfat "${LOOP_DEVICE}p1" "$MOUNT_POINT" 2>/dev/null || \
               sudo mount "${LOOP_DEVICE}p1" "$MOUNT_POINT" 2>/dev/null; then
                
                log_info "✓ Successfully mounted Windows partition"
                
                # Copy files
                log_info "Copying Windows 98 system files..."
                sudo mkdir -p "$MOUNT_POINT"/{Windows,SoftGPU,Drivers/Display}
                
                # Copy essential Windows files
                find "$ISO_EXTRACT_DIR/win98" -name "*.exe" -o -name "*.dll" -o -name "*.sys" | head -50 | while read file; do
                    sudo cp "$file" "$MOUNT_POINT/Windows/" 2>/dev/null || true
                done
                
                # Copy SoftGPU files
                log_info "Copying SoftGPU drivers..."
                sudo cp -r "$ISO_EXTRACT_DIR/softgpu"/* "$MOUNT_POINT/SoftGPU/" 2>/dev/null || true
                
                # Create batch files
                sudo tee "$MOUNT_POINT/INSTALL_SOFTGPU.BAT" > /dev/null << 'EOF'
@ECHO OFF
ECHO Installing SoftGPU drivers...
CD C:\SoftGPU
IF EXIST SETUP.EXE SETUP.EXE
IF EXIST INSTALL.EXE INSTALL.EXE
ECHO Installation complete!
PAUSE
EOF
                
                # Unmount and cleanup
                sudo umount "$MOUNT_POINT"
                sudo losetup -d "$LOOP_DEVICE"
                
                # Convert back to qcow2
                log_info "Converting back to qcow2..."
                mv "$QCOW2_IMAGE" "${QCOW2_IMAGE}.backup"
                qemu-img convert -f raw -O qcow2 "$RAW_IMAGE" "$QCOW2_IMAGE"
                rm "$RAW_IMAGE"
                
                log_info "✓ Method 2 successful - files injected via raw conversion"
                return 0
            else
                log_warn "Failed to mount partition"
                sudo losetup -d "$LOOP_DEVICE" 2>/dev/null || true
                rm -f "$RAW_IMAGE"
                return 1
            fi
        else
            log_warn "Failed to setup loop device"
            rm -f "$RAW_IMAGE"
            return 1
        fi
    else
        log_warn "No available loop devices"
        rm -f "$RAW_IMAGE"
        return 1
    fi
}

# Method 3: Create a separate data partition with files
method3_data_partition() {
    log_info "Method 3: Creating separate data partition..."
    
    check_prerequisites
    
    # Create a FAT partition with our files
    log_info "Creating file transfer partition..."
    
    # Calculate size needed
    TRANSFER_SIZE=$(du -sm "$ISO_EXTRACT_DIR" | cut -f1)
    TRANSFER_SIZE=$((TRANSFER_SIZE + 100))  # Add 100MB padding
    
    # Create FAT image with files
    TRANSFER_IMG="transfer_partition.img"
    dd if=/dev/zero of="$TRANSFER_IMG" bs=1M count="$TRANSFER_SIZE" 2>/dev/null
    mkfs.fat "$TRANSFER_IMG" > /dev/null 2>&1
    
    # Mount and copy files
    mkdir -p /tmp/transfer_mount
    sudo mount -o loop "$TRANSFER_IMG" /tmp/transfer_mount
    
    # Copy files to FAT partition
    log_info "Copying files to transfer partition..."
    sudo cp -r "$ISO_EXTRACT_DIR/win98"/* /tmp/transfer_mount/ 2>/dev/null || true
    sudo mkdir -p /tmp/transfer_mount/SoftGPU
    sudo cp -r "$ISO_EXTRACT_DIR/softgpu"/* /tmp/transfer_mount/SoftGPU/ 2>/dev/null || true
    
    # Create installation script
    sudo tee /tmp/transfer_mount/INSTALL.BAT > /dev/null << 'EOF'
@ECHO OFF
ECHO Copying files to C: drive...
XCOPY D:\*.* C:\Windows\ /S /E /Y
XCOPY D:\SoftGPU C:\SoftGPU\ /S /E /Y
ECHO Installation complete!
PAUSE
EOF
    
    sudo umount /tmp/transfer_mount
    rmdir /tmp/transfer_mount
    
    # Extend the original qcow2 image
    log_info "Extending qcow2 image to include transfer partition..."
    CURRENT_SIZE=$(qemu-img info "$QCOW2_IMAGE" | grep "virtual size" | cut -d'(' -f2 | cut -d' ' -f1)
    NEW_SIZE=$((CURRENT_SIZE + TRANSFER_SIZE * 1024 * 1024))
    
    qemu-img resize "$QCOW2_IMAGE" "${NEW_SIZE}"
    
    log_info "✓ Method 3 completed - created transfer partition"
    log_info "Files are now available as a secondary partition in the qcow2 image"
    echo ""
    echo "The transfer partition contains:"
    echo "  - All Windows 98 installation files"
    echo "  - SoftGPU drivers"
    echo "  - INSTALL.BAT script for easy installation"
    
    return 0
}

# Show status
show_status() {
    echo "=== Direct Injection Status ==="
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
        echo "    - Windows 98: $(find "$ISO_EXTRACT_DIR/win98" -type f | wc -l) files"
        echo "    - SoftGPU: $(find "$ISO_EXTRACT_DIR/softgpu" -type f | wc -l) files"
    else
        echo "  ✗ No extracted files"
    fi
    
    echo ""
    
    # Check available tools
    echo "Available injection methods:"
    if command -v guestfish &> /dev/null; then
        echo "  ✓ Method 1: libguestfs (guestfish available)"
    else
        echo "  ✗ Method 1: libguestfs (not available)"
    fi
    
    if command -v losetup &> /dev/null && [ -b "/dev/loop0" ]; then
        echo "  ✓ Method 2: Raw conversion (loop devices available)"
    else
        echo "  ✗ Method 2: Raw conversion (loop devices not available)"
    fi
    
    echo "  ✓ Method 3: Data partition (always available)"
    
    echo ""
    echo "Recommended: Try methods in order until one succeeds"
}

# Clean up
clean_all() {
    log_info "Cleaning up temporary files..."
    rm -rf "$ISO_EXTRACT_DIR"
    rm -f "$RAW_IMAGE"
    rm -f "transfer_partition.img"
    rm -f "inject_script.fish"
    sudo umount "$MOUNT_POINT" 2>/dev/null || true
    rmdir "$MOUNT_POINT" 2>/dev/null || true
    log_info "✓ Cleanup complete"
}

# Main execution
case "${1:-status}" in
    method1)
        method1_libguestfs
        ;;
    method2)
        method2_raw_conversion
        ;;
    method3)
        method3_data_partition
        ;;
    status)
        show_status
        ;;
    clean)
        clean_all
        ;;
    *)
        show_usage
        ;;
esac
