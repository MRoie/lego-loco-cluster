#!/bin/bash
# QEMU Win98 SoftGPU Manager - Consolidated script for all VM operations
# Combines functionality from multiple scripts into a single tool

set -e

# Configuration
WIN98_ISO="win98.iso"
SOFTGPU_ISO="softgpu.iso"
QCOW2_IMAGE="win98_softgpu.qcow2"
OUTPUT_IMAGE="../../images/win98.qcow2"
RAW_IMAGE="win98softgpu.raw"
MOUNT_POINT="/tmp/win98_mount"
ISO_EXTRACT_DIR="/tmp/iso_extracts"
TRANSFER_ISO="file_transfer.iso"
BACKUP_DIR="backups"

# VM Configuration
DISK_SIZE="2G"
RAM_MB=768
CPU_CORES=1
VNC_DISPLAY=0
MONITOR_PORT=6080

# Audio Configuration
AUDIO_BACKEND="pa"    # pa, alsa, oss, none
AUDIO_DEVICE="sb16"   # sb16, es1370, ac97, adlib
AUDIO_BUFFER="1024"   # Audio buffer size

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }
log_success() { echo -e "${PURPLE}[SUCCESS]${NC} $1"; }

# Show usage information
show_usage() {
    cat << 'EOF'
QEMU Win98 SoftGPU Manager
=========================

Usage: ./qemu-manager.sh <command> [options]

VM OPERATIONS:
  build               Build/install Windows 98 VM from ISO
  run                 Run the VM normally (production mode)
  run-debug           Run VM with debug console access
  run-build           Run VM for building/installation
  run-file-transfer   Run VM with file transfer ISO mounted

FILE INJECTION:
  inject-simple       Simple file injection using ISO method
  inject-direct       Direct injection using libguestfs
  inject-mount        Mount-based injection using loop devices
  inject-nbd          NBD-based injection (requires NBD support)
  create-transfer-iso Create ISO with files for transfer

DISK MANAGEMENT:
  mount               Mount qcow2 image for direct access
  unmount             Unmount and cleanup
  fix-disk            Fix disk detection issues
  convert-raw         Convert qcow2 to raw format
  convert-qcow2       Convert raw to qcow2 format

NETWORK:
  setup-network       Setup bridge and tap networking
  cleanup-network     Cleanup network interfaces

UTILITIES:
  status              Show current system status
  backup              Create backup of VM image
  restore             Restore from backup
  cleanup             Clean up temporary files
  check-prereqs       Check prerequisites and dependencies
  test-audio          Test audio system setup

EXAMPLES:
  ./qemu-manager.sh build                    # Build VM from scratch
  ./qemu-manager.sh inject-simple           # Inject files using ISO method
  ./qemu-manager.sh run                     # Run VM normally
  ./qemu-manager.sh status                  # Show current status

EOF
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing=0
    local tools=(qemu-system-i386 qemu-img 7z genisoimage losetup)
    
    for tool in "${tools[@]}"; do
        if ! command -v $tool &> /dev/null; then
            log_error "Missing tool: $tool"
            missing=1
        fi
    done
    
    # Check for optional tools
    local optional_tools=(virt-customize virt-filesystems nbdkit)
    for tool in "${optional_tools[@]}"; do
        if ! command -v $tool &> /dev/null; then
            log_warn "Optional tool missing: $tool (some features may not work)"
        else
            log_info "✓ Optional tool available: $tool"
        fi
    done
    
    if [ $missing -eq 1 ]; then
        log_error "Prerequisites not met. Install missing tools with:"
        echo "  sudo apt update && sudo apt install -y qemu-system-x86 qemu-utils p7zip-full genisoimage"
        echo "  sudo apt install -y libguestfs-tools nbdkit # Optional tools"
        exit 1
    fi
    
    log_success "All required prerequisites met"
}

# Setup network interfaces
setup_network() {
    log_info "Setting up network interfaces..."
    
    # Create bridge if not exists
    if ! ip link show br0 &>/dev/null; then
        log_info "Creating bridge br0..."
        sudo brctl addbr br0 || true
        sudo ip link set dev br0 up || true
    fi
    
    # Create tap device
    if ! ip link show tap0 &>/dev/null; then
        log_info "Creating tap0 interface..."
        sudo ip tuntap add tap0 mode tap user root || true
        sudo ip link set tap0 up || true
        sudo ip link set tap0 master br0 || true
    fi
    
    log_success "Network setup completed"
}

# Cleanup network interfaces
cleanup_network() {
    log_info "Cleaning up network interfaces..."
    
    if ip link show tap0 &>/dev/null; then
        sudo ip link delete tap0 || true
    fi
    
    if ip link show br0 &>/dev/null; then
        sudo ip link set br0 down || true
        sudo brctl delbr br0 || true
    fi
    
    log_success "Network cleanup completed"
}

# Build VM from scratch
build_vm() {
    log_info "Building Windows 98 VM from ISO..."
    
    if [ ! -f "$WIN98_ISO" ]; then
        log_error "Windows 98 ISO not found: $WIN98_ISO"
        exit 1
    fi
    
    if [ ! -f "$SOFTGPU_ISO" ]; then
        log_error "SoftGPU ISO not found: $SOFTGPU_ISO"
        exit 1
    fi
    
    # Create qcow2 image if it doesn't exist
    if [ ! -f "$QCOW2_IMAGE" ]; then
        log_info "Creating qcow2 image..."
        qemu-img create -f qcow2 "$QCOW2_IMAGE" "$DISK_SIZE"
    fi
    
    # Setup network first
    setup_network
    setup_audio
    
    # Get audio configuration for build (use none for installation)
    local audio_args=$(configure_win98_audio "none")
    local sound_device=$(configure_win98_sound_device "$AUDIO_DEVICE")
    
    log_info "Starting VM for installation..."
    qemu-system-i386 \
        -enable-kvm \
        -m $RAM_MB \
        -cpu pentium3 \
        -smp $CPU_CORES \
        -bios bios.bin \
        -hda "$QCOW2_IMAGE" \
        -drive file="$WIN98_ISO",media=cdrom,if=ide,index=1 \
        -drive file="Lego_Loco.iso",format=raw,if=ide,index=2,media=cdrom,readonly=on \
        -machine pc-i440fx-2.12 \
        -boot order=cd,menu=on \
        -vga std \
        $audio_args \
        $sound_device \
        -vnc 0.0.0.0:$VNC_DISPLAY \
        -rtc base=localtime \
        -netdev tap,id=net0,ifname=tap0,script=no,downscript=no \
        -device ne2k_pci,netdev=net0 \
        -usb \
        -device usb-tablet \
        -name "Win98 Installer with SoftGPU" \
        -monitor stdio
}

# Run VM normally
run_vm() {
    log_info "Starting Windows 98 VM..."
    
    if [ ! -f "$QCOW2_IMAGE" ]; then
        log_error "VM image not found: $QCOW2_IMAGE"
        log_info "Run './qemu-manager.sh build' first"
        exit 1
    fi
    
    setup_network
    setup_audio
    
    # Get audio configuration
    local audio_args=$(configure_win98_audio "$AUDIO_BACKEND" "$AUDIO_BUFFER")
    local sound_device=$(configure_win98_sound_device "$AUDIO_DEVICE")
    
    qemu-system-i386 \
        -enable-kvm \
        -m 768 \
        -cpu pentium3 \
        -smp 1 \
        -bios bios.bin \
        -hda "$QCOW2_IMAGE" \
        -drive file="$SOFTGPU_ISO",media=cdrom,if=ide,index=1 \
        -machine pc-i440fx-2.12 \
        -boot order=c,menu=on,splash-time=5000 \
        -vga std \
        -rtc base=localtime \
        -netdev tap,id=net0,ifname=tap0,script=no,downscript=no \
        -device ne2k_pci,netdev=net0 \
        $audio_args \
        $sound_device \
        -usb \
        -device usb-tablet \
        -name "Windows 98" \
        -no-shutdown \
        -no-reboot \
        -vnc 0.0.0.0:$VNC_DISPLAY &
    
    # Start noVNC if available
    if command -v websockify &> /dev/null; then
        log_info "Starting noVNC on port $MONITOR_PORT..."
        websockify --web=/usr/share/novnc/ $MONITOR_PORT localhost:590$VNC_DISPLAY
    else
        log_warn "websockify not available. Connect via VNC to localhost:590$VNC_DISPLAY"
        wait
    fi
}

# Run VM in debug mode
run_vm_debug() {
    log_info "Starting Windows 98 VM in debug mode..."
    
    # Setup network first
    setup_network
    setup_audio
    
    # Get audio configuration
    local audio_args=$(configure_win98_audio "$AUDIO_BACKEND" "$AUDIO_BUFFER")
    local sound_device=$(configure_win98_sound_device "$AUDIO_DEVICE")
    
    qemu-system-i386 \
        -enable-kvm \
        -m 768 \
        -cpu pentium3 \
        -smp 1 \
        -bios bios.bin \
        -hda "$QCOW2_IMAGE" \
        -drive file="$SOFTGPU_ISO",media=cdrom,if=ide,index=1 \
        -machine pc-i440fx-2.12 \
        -boot order=c,menu=on,splash-time=5000 \
        -vga std \
        $audio_args \
        $sound_device \
        -vnc 0.0.0.0:$VNC_DISPLAY \
        -rtc base=localtime \
        -netdev tap,id=net0,ifname=tap0,script=no,downscript=no \
        -device ne2k_pci,netdev=net0 \
        -usb \
        -device usb-tablet \
        -name "Windows 98 Debug" \
        -no-shutdown \
        -no-reboot \
        -monitor stdio \
        -serial file:debug.log
}

# Create transfer ISO
create_transfer_iso() {
    local source_dir="${1:-$ISO_EXTRACT_DIR}"
    
    if [ ! -d "$source_dir" ]; then
        log_error "Source directory not found: $source_dir"
        log_info "Run file extraction first"
        exit 1
    fi
    
    log_info "Creating transfer ISO from $source_dir..."
    genisoimage -o "$TRANSFER_ISO" -R -J -joliet-long "$source_dir"
    
    log_success "Created $TRANSFER_ISO"
    log_info "You can mount this as a CD-ROM in QEMU with:"
    log_info "  -drive file=\"$TRANSFER_ISO\",if=ide,index=2,media=cdrom,readonly=on"
}

# Extract files from ISOs
extract_files() {
    log_info "Extracting files from ISOs..."
    
    # Clean and create extraction directory
    rm -rf "$ISO_EXTRACT_DIR"
    mkdir -p "$ISO_EXTRACT_DIR"/{win98,softgpu,combined}
    
    if [ -f "$WIN98_ISO" ]; then
        log_info "Extracting Windows 98 files..."
        7z x "$WIN98_ISO" -o"$ISO_EXTRACT_DIR/win98" -y > /dev/null 2>&1
    fi
    
    if [ -f "$SOFTGPU_ISO" ]; then
        log_info "Extracting SoftGPU files..."
        7z x "$SOFTGPU_ISO" -o"$ISO_EXTRACT_DIR/softgpu" -y > /dev/null 2>&1
    fi
    
    # Copy important files to combined directory
    if [ -d "$ISO_EXTRACT_DIR/softgpu" ]; then
        cp -r "$ISO_EXTRACT_DIR/softgpu"/* "$ISO_EXTRACT_DIR/combined/" 2>/dev/null || true
    fi
    
    local total_size=$(du -sh "$ISO_EXTRACT_DIR" 2>/dev/null | cut -f1 || echo "unknown")
    log_success "Extraction completed. Total size: $total_size"
}

# Simple file injection using ISO method
inject_simple() {
    log_info "Starting simple file injection..."
    
    extract_files
    create_transfer_iso "$ISO_EXTRACT_DIR/combined"
    
    log_info "Running VM with transfer ISO..."
    qemu-system-i386 \
        -enable-kvm \
        -m $RAM_MB \
        -cpu pentium2 \
        -smp $CPU_CORES \
        -hda "$QCOW2_IMAGE" \
        -drive file="$TRANSFER_ISO",if=ide,index=1,media=cdrom,readonly=on \
        -machine pc-i440fx-2.12 \
        -boot order=c,menu=on \
        -vga std \
        -vnc 0.0.0.0:$VNC_DISPLAY \
        -name "Windows 98 File Transfer" \
        -monitor stdio
}

# Direct injection using libguestfs
inject_direct() {
    log_info "Attempting direct file injection..."
    
    if ! command -v virt-customize &> /dev/null; then
        log_error "virt-customize not available. Install with: sudo apt install libguestfs-tools"
        exit 1
    fi
    
    extract_files
    
    # Create backup
    if [ ! -f "${QCOW2_IMAGE}.backup" ]; then
        log_info "Creating backup..."
        cp "$QCOW2_IMAGE" "${QCOW2_IMAGE}.backup"
    fi
    
    log_info "Injecting files directly into qcow2..."
    if virt-customize -a "$QCOW2_IMAGE" \
        --mkdir /SoftGPU \
        --copy-in "$ISO_EXTRACT_DIR/softgpu":/SoftGPU \
        --write "/SUCCESS.TXT:Files injected without booting!" 2>/dev/null; then
        
        log_success "Direct injection successful!"
    else
        log_error "Direct injection failed. Try alternative methods."
        exit 1
    fi
}

# Mount-based injection
inject_mount() {
    log_info "Starting mount-based injection..."
    
    extract_files
    mount_image
    
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        log_info "Copying files to mounted image..."
        sudo cp -r "$ISO_EXTRACT_DIR/softgpu"/* "$MOUNT_POINT/" || true
        sync
        
        log_success "Files copied to mounted image"
        unmount_image
    else
        log_error "Failed to mount image"
        exit 1
    fi
}

# Mount qcow2 image
mount_image() {
    log_info "Mounting qcow2 image..."
    
    # Convert to raw if needed
    if [ ! -f "$RAW_IMAGE" ] || [ "$QCOW2_IMAGE" -nt "$RAW_IMAGE" ]; then
        log_info "Converting qcow2 to raw..."
        qemu-img convert -f qcow2 -O raw "$QCOW2_IMAGE" "$RAW_IMAGE"
    fi
    
    # Find available loop device
    local loop_device=$(sudo losetup -f)
    log_info "Using loop device: $loop_device"
    
    # Setup loop device
    sudo losetup "$loop_device" "$RAW_IMAGE"
    
    # Create mount point
    sudo mkdir -p "$MOUNT_POINT"
    
    # Try to mount (may fail if filesystem is not supported)
    if sudo mount "$loop_device" "$MOUNT_POINT" 2>/dev/null; then
        log_success "Image mounted at $MOUNT_POINT"
    else
        log_warn "Direct mount failed (probably NTFS/FAT). Loop device still available at $loop_device"
    fi
}

# Unmount image
unmount_image() {
    log_info "Unmounting image..."
    
    # Unmount if mounted
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        sudo umount "$MOUNT_POINT" || true
    fi
    
    # Clean up loop devices
    for loop in $(losetup -a | grep "$RAW_IMAGE" | cut -d: -f1); do
        log_info "Detaching $loop..."
        sudo losetup -d "$loop" || true
    done
    
    log_success "Unmount completed"
}

# Fix disk issues
fix_disk() {
    log_info "Attempting to fix disk issues..."
    
    # Check image integrity
    log_info "Checking image integrity..."
    qemu-img check "$QCOW2_IMAGE"
    
    # Try to repair if needed
    log_info "Attempting repair..."
    qemu-img check -r all "$QCOW2_IMAGE" || true
    
    log_success "Disk check/repair completed"
}

# Create backup
create_backup() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/${QCOW2_IMAGE%.qcow2}_$timestamp.qcow2"
    
    mkdir -p "$BACKUP_DIR"
    
    log_info "Creating backup: $backup_file"
    cp "$QCOW2_IMAGE" "$backup_file"
    
    log_success "Backup created: $backup_file"
}

# Show status
show_status() {
    echo "QEMU Win98 SoftGPU Manager Status"
    echo "================================="
    echo ""
    
    # Check files
    echo "FILES:"
    for file in "$WIN98_ISO" "$SOFTGPU_ISO" "$QCOW2_IMAGE"; do
        if [ -f "$file" ]; then
            local size=$(du -h "$file" | cut -f1)
            echo "  ✓ $file ($size)"
        else
            echo "  ✗ $file (missing)"
        fi
    done
    echo ""
    
    # Check extracted files
    if [ -d "$ISO_EXTRACT_DIR" ]; then
        local extract_size=$(du -sh "$ISO_EXTRACT_DIR" 2>/dev/null | cut -f1 || echo "unknown")
        echo "  ✓ Extracted files: $extract_size"
    else
        echo "  ✗ No extracted files"
    fi
    echo ""
    
    # Check processes
    echo "PROCESSES:"
    if pgrep -f "qemu-system-i386" > /dev/null; then
        echo "  ✓ QEMU running (PID: $(pgrep -f "qemu-system-i386"))"
    else
        echo "  ✗ QEMU not running"
    fi
    
    if pgrep -f "websockify" > /dev/null; then
        echo "  ✓ noVNC running (PID: $(pgrep -f "websockify"))"
    else
        echo "  ✗ noVNC not running"
    fi
    echo ""
    
    # Check network
    echo "NETWORK:"
    if ip link show br0 &>/dev/null; then
        echo "  ✓ Bridge br0 exists"
    else
        echo "  ✗ Bridge br0 missing"
    fi
    
    if ip link show tap0 &>/dev/null; then
        echo "  ✓ TAP tap0 exists"
    else
        echo "  ✗ TAP tap0 missing"
    fi
    echo ""
    
    # Check mounts
    echo "MOUNTS:"
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        echo "  ✓ Image mounted at $MOUNT_POINT"
    else
        echo "  ✗ No image mounted"
    fi
    
    # Check loop devices
    local loop_count=0
    if losetup -a | grep -q "$RAW_IMAGE" 2>/dev/null; then
        loop_count=$(losetup -a | grep "$RAW_IMAGE" 2>/dev/null | wc -l)
    fi
    if [ "$loop_count" -gt 0 ]; then
        echo "  ⚠ $loop_count loop device(s) active"
    fi
}

# Cleanup temporary files
cleanup() {
    log_info "Cleaning up temporary files..."
    
    # Stop QEMU processes
    if pgrep -f "qemu-system-i386" > /dev/null; then
        log_info "Stopping QEMU processes..."
        pkill -f "qemu-system-i386" || true
        sleep 2
    fi
    
    # Stop noVNC
    if pgrep -f "websockify" > /dev/null; then
        log_info "Stopping noVNC..."
        pkill -f "websockify" || true
    fi
    
    # Unmount if mounted
    unmount_image
    
    # Clean up network
    cleanup_network
    
    # Remove temporary files
    rm -rf "$ISO_EXTRACT_DIR"
    rm -f "$RAW_IMAGE"
    rm -f "$TRANSFER_ISO"
    rm -f debug.log
    
    log_success "Cleanup completed"
}

# Setup audio system
setup_audio() {
    log_info "Setting up audio system..."
    
    # Start PulseAudio if not running
    if ! pgrep -x "pulseaudio" > /dev/null; then
        log_info "Starting PulseAudio daemon..."
        if pulseaudio --start --exit-idle-time=-1 2>/dev/null; then
            log_success "PulseAudio started successfully"
        else
            log_warn "Failed to start PulseAudio, audio may not work"
        fi
    else
        log_info "PulseAudio already running"
    fi
    
    # Check audio sinks
    if command -v pactl &> /dev/null; then
        local sinks=$(pactl list sinks short | wc -l)
        if [ "$sinks" -gt 0 ]; then
            log_success "Audio sinks available: $sinks"
        else
            log_warn "No audio sinks found"
        fi
    fi
}

# Configure Win98 audio backend
configure_win98_audio() {
    local backend="${1:-pa}"
    local buffer="${2:-1024}"
    
    case "$backend" in
        "pa"|"pulseaudio")
            echo "-audiodev pa,id=snd0,server=unix:/run/user/$UID/pulse/native"
            ;;
        "alsa")
            echo "-audiodev alsa,id=snd0"
            ;;
        "oss")
            echo "-audiodev oss,id=snd0"
            ;;
        "none")
            echo "-audiodev none,id=snd0"
            ;;
        *)
            log_warn "Unknown audio backend: $backend, using PulseAudio"
            echo "-audiodev pa,id=snd0"
            ;;
    esac
}

# Configure Win98 sound device
configure_win98_sound_device() {
    local device="${1:-sb16}"
    
    case "$device" in
        "sb16")
            echo "-device sb16,audiodev=snd0"
            ;;
        "es1370")
            echo "-device es1370,audiodev=snd0"
            ;;
        "ac97")
            echo "-device ac97,audiodev=snd0"
            ;;
        "adlib")
            echo "-device adlib,audiodev=snd0"
            ;;
        *)
            log_warn "Unknown sound device: $device, using Sound Blaster 16"
            echo "-device sb16,audiodev=snd0"
            ;;
    esac
}

# Test audio system
test_audio() {
    log_info "Testing audio system..."
    
    # Check PulseAudio
    if pgrep -x "pulseaudio" > /dev/null; then
        log_success "✓ PulseAudio running (PID: $(pgrep -x "pulseaudio"))"
    else
        log_error "✗ PulseAudio not running"
        return 1
    fi
    
    # Check audio sinks
    if command -v pactl &> /dev/null; then
        local sink_count=$(pactl list sinks short | wc -l)
        if [ "$sink_count" -gt 0 ]; then
            log_success "✓ Audio sinks available: $sink_count"
            
            # List available sinks
            log_info "Available audio sinks:"
            pactl list sinks short | while read line; do
                log_info "  $line"
            done
            
            # Test audio playback if speaker-test is available
            if command -v speaker-test &> /dev/null; then
                log_info "Testing audio playback for 2 seconds..."
                timeout 2 speaker-test -t sine -f 440 -l 1 > /dev/null 2>&1 || true
                log_success "Audio test completed"
            fi
            
        else
            log_error "✗ No audio sinks found"
            return 1
        fi
    else
        log_warn "⚠ pactl not available, cannot test audio sinks"
    fi
    
    log_success "Audio system test completed"
}

# Main script logic
main() {
    local command="${1:-help}"
    
    case "$command" in
        "help"|"--help"|"-h")
            show_usage
            ;;
        "check-prereqs")
            check_prerequisites
            ;;
        "build")
            check_prerequisites
            build_vm
            ;;
        "run")
            run_vm
            ;;
        "run-debug")
            run_vm_debug
            ;;
        "run-file-transfer")
            inject_simple
            ;;
        "inject-simple")
            inject_simple
            ;;
        "inject-direct")
            inject_direct
            ;;
        "inject-mount")
            inject_mount
            ;;
        "create-transfer-iso")
            extract_files
            create_transfer_iso
            ;;
        "mount")
            mount_image
            ;;
        "unmount")
            unmount_image
            ;;
        "fix-disk")
            fix_disk
            ;;
        "setup-network")
            setup_network
            ;;
        "cleanup-network")
            cleanup_network
            ;;
        "status")
            show_status
            ;;
        "backup")
            create_backup
            ;;
        "cleanup")
            cleanup
            ;;
        "test-audio")
            test_audio
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
