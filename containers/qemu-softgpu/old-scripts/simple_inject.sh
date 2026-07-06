#!/bin/bash
# Simple file injection using QEMU guest agent approach
# This bypasses container limitations by using QEMU itself

set -e

# Configuration
WIN98_ISO="win98.iso"
SOFTGPU_ISO="softgpu.iso" 
QCOW2_IMAGE="win98_softgpu.qcow2"
ISO_EXTRACT_DIR="/tmp/iso_extracts"
TRANSFER_ISO="file_transfer.iso"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

show_usage() {
    echo "Simple File Injection for Windows 98 VM"
    echo "========================================"
    echo ""
    echo "Usage: $0 [prepare|create-iso|run-vm|status|clean]"
    echo ""
    echo "Commands:"
    echo "  prepare     - Extract files from ISOs"
    echo "  create-iso  - Create transfer ISO with files"
    echo "  run-vm      - Run VM with transfer ISO attached"
    echo "  status      - Show current status"
    echo "  clean       - Clean up temporary files"
    echo ""
    echo "Workflow:"
    echo "  1. $0 prepare       # Extract Windows 98 and SoftGPU files"
    echo "  2. $0 create-iso    # Create ISO with essential files"
    echo "  3. $0 run-vm        # Run Windows 98 VM with transfer ISO"
    echo "  4. In Windows: Copy files from D: to C: drive"
}

# Extract files from ISOs
prepare_files() {
    log_info "Preparing files for injection..."
    
    # Check prerequisites
    for file in "$WIN98_ISO" "$SOFTGPU_ISO" "$QCOW2_IMAGE"; do
        if [ ! -f "$file" ]; then
            log_error "Missing file: $file"
            exit 1
        fi
    done
    
    if ! command -v 7z &> /dev/null; then
        log_error "7z not found. Install with: sudo apt install p7zip-full"
        exit 1
    fi
    
    # Clean and create extraction directory
    rm -rf "$ISO_EXTRACT_DIR"
    mkdir -p "$ISO_EXTRACT_DIR"/{win98,softgpu,transfer}
    
    # Extract Windows 98 ISO
    log_info "Extracting Windows 98 files..."
    7z x "$WIN98_ISO" -o"$ISO_EXTRACT_DIR/win98" -y > /dev/null 2>&1
    
    # Extract SoftGPU ISO  
    log_info "Extracting SoftGPU files..."
    7z x "$SOFTGPU_ISO" -o"$ISO_EXTRACT_DIR/softgpu" -y > /dev/null 2>&1
    
    # Copy essential files to transfer directory
    log_info "Selecting essential files for transfer..."
    
    # Create Windows directory structure in transfer area
    mkdir -p "$ISO_EXTRACT_DIR/transfer"/{Windows,Drivers,SoftGPU,Tools}
    
    # Copy essential Windows 98 system files
    if [ -d "$ISO_EXTRACT_DIR/win98/WIN98" ]; then
        log_info "Copying Windows 98 system files..."
        cp -r "$ISO_EXTRACT_DIR/win98/WIN98"/* "$ISO_EXTRACT_DIR/transfer/Windows/" 2>/dev/null || true
    fi
    
    # Copy important Windows executables and drivers
    for ext in exe dll sys inf cab; do
        find "$ISO_EXTRACT_DIR/win98" -name "*.$ext" -type f | head -50 | while read file; do
            cp "$file" "$ISO_EXTRACT_DIR/transfer/Windows/" 2>/dev/null || true
        done
    done
    
    # Copy all SoftGPU files
    log_info "Copying SoftGPU drivers..."
    cp -r "$ISO_EXTRACT_DIR/softgpu"/* "$ISO_EXTRACT_DIR/transfer/SoftGPU/" 2>/dev/null || true
    
    # Create installation batch files
    cat > "$ISO_EXTRACT_DIR/transfer/INSTALL_ALL.BAT" << 'EOF'
@ECHO OFF
ECHO.
ECHO ================================================
ECHO  Windows 98 + SoftGPU File Installation
ECHO ================================================
ECHO.
ECHO This will copy essential files to your C: drive.
ECHO.
PAUSE
ECHO.

ECHO Copying Windows system files...
IF EXIST D:\Windows XCOPY D:\Windows C:\Windows /S /E /Y
IF EXIST D:\Windows XCOPY D:\Windows C:\WINDOWS /S /E /Y

ECHO.
ECHO Copying SoftGPU drivers...
IF NOT EXIST C:\Drivers\Display MKDIR C:\Drivers\Display
XCOPY D:\SoftGPU C:\Drivers\Display /S /E /Y
XCOPY D:\SoftGPU C:\SoftGPU /S /E /Y

ECHO.
ECHO Creating shortcuts...
ECHO @ECHO OFF > C:\INSTALL_SOFTGPU.BAT
ECHO CD C:\SoftGPU >> C:\INSTALL_SOFTGPU.BAT
ECHO IF EXIST SETUP.EXE SETUP.EXE >> C:\INSTALL_SOFTGPU.BAT
ECHO IF EXIST INSTALL.EXE INSTALL.EXE >> C:\INSTALL_SOFTGPU.BAT

ECHO.
ECHO ================================================
ECHO Installation complete!
ECHO.
ECHO Next steps:
ECHO 1. Run C:\INSTALL_SOFTGPU.BAT to install SoftGPU
ECHO 2. Restart Windows 98
ECHO ================================================
PAUSE
EOF
    
    # Create individual installation scripts
    cat > "$ISO_EXTRACT_DIR/transfer/INSTALL_SOFTGPU_ONLY.BAT" << 'EOF'
@ECHO OFF
ECHO Installing SoftGPU drivers...
IF NOT EXIST C:\SoftGPU MKDIR C:\SoftGPU
XCOPY D:\SoftGPU C:\SoftGPU /S /E /Y
CD C:\SoftGPU
IF EXIST SETUP.EXE SETUP.EXE
IF EXIST INSTALL.EXE INSTALL.EXE
ECHO SoftGPU installation complete!
PAUSE
EOF
    
    # Show what we prepared
    log_info "Files prepared for transfer:"
    echo "Windows files: $(find "$ISO_EXTRACT_DIR/transfer/Windows" -type f | wc -l) files"
    echo "SoftGPU files: $(find "$ISO_EXTRACT_DIR/transfer/SoftGPU" -type f | wc -l) files"
    echo "Total size: $(du -sh "$ISO_EXTRACT_DIR/transfer" | cut -f1)"
    
    log_info "✓ File preparation complete"
}

# Create transfer ISO
create_transfer_iso() {
    log_info "Creating transfer ISO..."
    
    if [ ! -d "$ISO_EXTRACT_DIR/transfer" ]; then
        log_error "No transfer files found. Run 'prepare' first."
        exit 1
    fi
    
    if ! command -v genisoimage &> /dev/null; then
        log_error "genisoimage not found. Install with: sudo apt install genisoimage"
        exit 1
    fi
    
    # Create ISO with Windows-friendly options
    genisoimage \
        -o "$TRANSFER_ISO" \
        -R \
        -J \
        -joliet-long \
        -V "TRANSFER" \
        -A "Windows 98 File Transfer" \
        "$ISO_EXTRACT_DIR/transfer"
    
    log_info "✓ Created $TRANSFER_ISO ($(du -h "$TRANSFER_ISO" | cut -f1))"
    echo ""
    echo "The transfer ISO contains:"
    echo "  - Windows 98 system files"
    echo "  - SoftGPU drivers and installation files"
    echo "  - Automated installation batch files"
}

# Run VM with transfer ISO
run_vm_with_transfer() {
    log_info "Running Windows 98 VM with transfer ISO..."
    
    if [ ! -f "$TRANSFER_ISO" ]; then
        log_error "Transfer ISO not found. Run 'create-iso' first."
        exit 1
    fi
    
    if [ ! -f "$QCOW2_IMAGE" ]; then
        log_error "Windows 98 qcow2 image not found: $QCOW2_IMAGE"
        exit 1
    fi
    
    log_info "Starting VM with transfer ISO attached..."
    echo ""
    echo "VM will start with:"
    echo "  - C: drive = Windows 98 installation"
    echo "  - D: drive = Transfer ISO with files"
    echo ""
    echo "In Windows 98:"
    echo "  1. Open D: drive in Explorer"
    echo "  2. Double-click INSTALL_ALL.BAT"
    echo "  3. Follow the prompts to copy files"
    echo ""
    
    # Create enhanced VM script
    cat > run_transfer_vm.sh << EOF
#!/bin/bash
echo "Starting Windows 98 VM with file transfer capability..."

qemu-system-i386 \\
  -enable-kvm \\
  -m 512 \\
  -cpu pentium2 \\
  -smp 1 \\
  -hda "$QCOW2_IMAGE" \\
  -cdrom "$TRANSFER_ISO" \\
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
  -name "Windows 98 + File Transfer" \\
  -monitor stdio
EOF
    
    chmod +x run_transfer_vm.sh
    
    echo "Created run_transfer_vm.sh - execute this to start the VM"
    echo ""
    echo "Or run directly:"
    echo "./run_transfer_vm.sh"
}

# Show status
show_status() {
    echo "=== Simple File Injection Status ==="
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
        if [ -d "$ISO_EXTRACT_DIR/transfer" ]; then
            echo "    ✓ Transfer files ready ($(du -sh "$ISO_EXTRACT_DIR/transfer" | cut -f1))"
        else
            echo "    ✗ Transfer files not prepared"
        fi
    else
        echo "  ✗ No extracted files"
    fi
    
    echo ""
    
    # Check transfer ISO
    echo "Transfer ISO:"
    if [ -f "$TRANSFER_ISO" ]; then
        echo "  ✓ $TRANSFER_ISO ($(du -h "$TRANSFER_ISO" | cut -f1))"
    else
        echo "  ✗ Transfer ISO not created"
    fi
    
    echo ""
    
    # Check VM script
    echo "VM script:"
    if [ -f "run_transfer_vm.sh" ]; then
        echo "  ✓ run_transfer_vm.sh ready"
    else
        echo "  ✗ VM script not created"
    fi
    
    echo ""
    
    # Show next steps
    echo "Next steps:"
    if [ ! -d "$ISO_EXTRACT_DIR" ]; then
        echo "  1. Run: $0 prepare"
    elif [ ! -f "$TRANSFER_ISO" ]; then
        echo "  1. Run: $0 create-iso"
    elif [ ! -f "run_transfer_vm.sh" ]; then
        echo "  1. Run: $0 run-vm"
    else
        echo "  1. Execute: ./run_transfer_vm.sh"
        echo "  2. In Windows 98, run D:\\INSTALL_ALL.BAT"
    fi
}

# Clean up
clean_all() {
    log_info "Cleaning up temporary files..."
    rm -rf "$ISO_EXTRACT_DIR"
    rm -f "$TRANSFER_ISO"
    rm -f run_transfer_vm.sh
    log_info "✓ Cleanup complete"
}

# Main command handling
case "${1:-status}" in
    prepare)
        prepare_files
        ;;
    create-iso)
        create_transfer_iso
        ;;
    run-vm)
        run_vm_with_transfer
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
