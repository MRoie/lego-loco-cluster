#!/bin/bash
# Fast file transfer to Windows 98 VM using ISO method
# No need to boot Windows - just mount the ISO as a second CD-ROM

set -e

TRANSFER_ISO="transfer.iso"
TRANSFER_DIR="/tmp/transfer_files"

show_usage() {
    echo "Usage: $0 [create|add|build|clean] [source_files...]"
    echo ""
    echo "Commands:"
    echo "  create <files...>  - Create new transfer ISO with files"
    echo "  add <files...>     - Add files to staging area"
    echo "  build             - Build ISO from staging area"
    echo "  clean             - Clean up staging area and ISO"
    echo "  show              - Show current staging area contents"
    echo ""
    echo "Examples:"
    echo "  $0 create /path/to/game.exe /path/to/patch.zip"
    echo "  $0 add /path/to/more/files/*"
    echo "  $0 build"
    echo ""
    echo "Then modify your QEMU script to include:"
    echo "  -drive file=\"$TRANSFER_ISO\",if=ide,index=2,media=cdrom,readonly=on \\"
}

# Initialize staging directory
init_staging() {
    if [ ! -d "$TRANSFER_DIR" ]; then
        echo "Creating staging directory: $TRANSFER_DIR"
        mkdir -p "$TRANSFER_DIR"
    fi
}

# Add files to staging area
add_files() {
    if [ $# -eq 0 ]; then
        echo "Error: No files specified"
        return 1
    fi
    
    init_staging
    
    for file in "$@"; do
        if [ -e "$file" ]; then
            echo "Adding: $file"
            if [ -d "$file" ]; then
                cp -r "$file" "$TRANSFER_DIR/"
            else
                cp "$file" "$TRANSFER_DIR/"
            fi
        else
            echo "Warning: File not found: $file"
        fi
    done
    
    echo "Files staged in $TRANSFER_DIR"
}

# Build ISO from staging area
build_iso() {
    if [ ! -d "$TRANSFER_DIR" ] || [ -z "$(ls -A "$TRANSFER_DIR" 2>/dev/null)" ]; then
        echo "Error: No files in staging directory. Use 'add' command first."
        return 1
    fi
    
    echo "Building ISO: $TRANSFER_ISO"
    echo "Contents:"
    ls -la "$TRANSFER_DIR"
    
    # Create ISO with Windows-friendly options
    genisoimage \
        -o "$TRANSFER_ISO" \
        -R \
        -J \
        -joliet-long \
        -V "TRANSFER" \
        -A "File Transfer Disk" \
        "$TRANSFER_DIR"
    
    echo "✓ Created $TRANSFER_ISO ($(du -h "$TRANSFER_ISO" | cut -f1))"
    echo ""
    echo "To use this ISO in your VM, add this line to your QEMU command:"
    echo "  -drive file=\"$TRANSFER_ISO\",if=ide,index=2,media=cdrom,readonly=on \\"
    echo ""
    echo "In Windows 98, the files will appear on drive D: or E:"
}

# Create ISO directly from files (convenience function)
create_iso() {
    if [ $# -eq 0 ]; then
        echo "Error: No files specified"
        show_usage
        return 1
    fi
    
    # Clean and recreate staging
    clean_all
    add_files "$@"
    build_iso
}

# Show staging contents
show_staging() {
    if [ -d "$TRANSFER_DIR" ]; then
        echo "Staging directory contents ($TRANSFER_DIR):"
        ls -la "$TRANSFER_DIR"
        echo ""
        echo "Total size: $(du -sh "$TRANSFER_DIR" | cut -f1)"
    else
        echo "No staging directory found"
    fi
    
    if [ -f "$TRANSFER_ISO" ]; then
        echo ""
        echo "Current transfer ISO:"
        ls -lh "$TRANSFER_ISO"
    fi
}

# Clean up
clean_all() {
    echo "Cleaning up..."
    rm -rf "$TRANSFER_DIR"
    rm -f "$TRANSFER_ISO"
    echo "✓ Cleaned staging directory and ISO"
}

# Update VM script to include transfer ISO
update_vm_script() {
    local VM_SCRIPT="build_win98_vm.sh"
    
    if [ ! -f "$VM_SCRIPT" ]; then
        echo "VM script not found: $VM_SCRIPT"
        return 1
    fi
    
    # Check if transfer ISO line already exists
    if grep -q "transfer.iso" "$VM_SCRIPT"; then
        echo "Transfer ISO already configured in $VM_SCRIPT"
        return 0
    fi
    
    echo "Would you like me to automatically add the transfer ISO to your VM script? (y/n)"
    read -r response
    if [[ "$response" =~ ^[Yy] ]]; then
        # Add the transfer ISO line before the -name line
        sed -i '/^[[:space:]]*-name/i \  -drive file="transfer.iso",if=ide,index=2,media=cdrom,readonly=on \\' "$VM_SCRIPT"
        echo "✓ Added transfer ISO to $VM_SCRIPT"
    fi
}

# Main command handling
case "${1:-}" in
    create)
        shift
        create_iso "$@"
        ;;
    add)
        shift
        add_files "$@"
        ;;
    build)
        build_iso
        ;;
    clean)
        clean_all
        ;;
    show)
        show_staging
        ;;
    update-vm)
        update_vm_script
        ;;
    *)
        show_usage
        ;;
esac
