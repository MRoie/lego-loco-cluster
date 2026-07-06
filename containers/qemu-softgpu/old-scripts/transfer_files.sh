#!/bin/bash
# Alternative methods to copy files to qcow2 image when NBD is not available
# These methods work in container environments

set -e

IMAGE_PATH="../../images/win98.qcow2"

echo "=== Method 1: Create a file transfer ISO ==="
echo "This creates an ISO with your files that you can mount in the VM"
echo ""

create_transfer_iso() {
    local SOURCE_DIR="$1"
    local ISO_NAME="${2:-transfer.iso}"
    
    if [ ! -d "$SOURCE_DIR" ]; then
        echo "Error: Source directory $SOURCE_DIR does not exist"
        return 1
    fi
    
    echo "Creating ISO from $SOURCE_DIR..."
    genisoimage -o "$ISO_NAME" -R -J -joliet-long "$SOURCE_DIR"
    echo "Created $ISO_NAME - you can mount this as a second CD-ROM in QEMU"
    echo ""
    echo "To use in your VM script, add:"
    echo "  -drive file=\"$ISO_NAME\",if=ide,index=2,media=cdrom,readonly=on \\"
}

echo "=== Method 2: Use QEMU with temporary boot disk ==="
echo "Boot a Linux rescue system to copy files"
echo ""

create_rescue_script() {
    cat > transfer_files.sh << 'EOF'
#!/bin/bash
# This script runs a minimal Linux system to transfer files

QCOW2_IMAGE="../../images/win98.qcow2"
FILES_ISO="transfer.iso"  # ISO with your files

qemu-system-i386 \
  -enable-kvm \
  -m 512 \
  -drive file="$QCOW2_IMAGE",format=qcow2,if=ide,index=0,media=disk \
  -cdrom ubuntu-mini.iso \
  -drive file="$FILES_ISO",if=ide,index=2,media=cdrom,readonly=on \
  -boot order=cd \
  -vnc 0.0.0.0:1 \
  -name "File Transfer System"

# In the Linux rescue system:
# 1. Mount the Windows partition: mount /dev/hda1 /mnt
# 2. Mount the transfer ISO: mount /dev/hdc /media
# 3. Copy files: cp /media/* /mnt/
EOF
    chmod +x transfer_files.sh
    echo "Created transfer_files.sh - download a minimal Linux ISO to use this method"
}

echo "=== Method 3: Modify your VM script to include file transfer ==="
echo "Add a second CD-ROM with your files"
echo ""

show_vm_modification() {
    echo "In your build_win98_vm.sh, add an additional drive:"
    echo ""
    echo "  -drive file=\"transfer.iso\",if=ide,index=2,media=cdrom,readonly=on \\"
    echo ""
    echo "Then in Windows 98:"
    echo "1. The transfer CD will appear as D: or E: drive"
    echo "2. Copy files from the CD to C: drive using Windows Explorer"
}

echo "=== Method 4: Use qemu-img to create a FAT partition ==="
echo "Create a small FAT image that Windows 98 can read"
echo ""

create_fat_transfer() {
    local SIZE_MB="${1:-100}"
    local TRANSFER_IMG="transfer.img"
    
    echo "Creating ${SIZE_MB}MB FAT image..."
    dd if=/dev/zero of="$TRANSFER_IMG" bs=1M count="$SIZE_MB"
    mkfs.fat "$TRANSFER_IMG"
    
    # Mount and copy files
    mkdir -p /tmp/fat_mount
    sudo mount -o loop "$TRANSFER_IMG" /tmp/fat_mount
    echo "Mounted $TRANSFER_IMG at /tmp/fat_mount"
    echo "Copy your files to /tmp/fat_mount/"
    echo "Then unmount with: sudo umount /tmp/fat_mount"
    echo ""
    echo "Add to your QEMU command:"
    echo "  -drive file=\"$TRANSFER_IMG\",if=ide,index=2,media=disk \\"
}

echo "=== Method 5: Direct qcow2 manipulation (Advanced) ==="
echo "Use qemu-img to resize and modify the image"
echo ""

show_advanced_method() {
    echo "# Convert qcow2 to raw for easier manipulation"
    echo "qemu-img convert -f qcow2 -O raw $IMAGE_PATH temp.raw"
    echo ""
    echo "# Mount the raw image (if loop device is available)"
    echo "sudo losetup /dev/loop0 temp.raw"
    echo "sudo mount /dev/loop0p1 /mnt"
    echo "# Copy files to /mnt"
    echo "sudo umount /mnt"
    echo "sudo losetup -d /dev/loop0"
    echo ""
    echo "# Convert back to qcow2"
    echo "qemu-img convert -f raw -O qcow2 temp.raw $IMAGE_PATH"
    echo "rm temp.raw"
}

# Main menu
case "${1:-menu}" in
    "iso")
        if [ -z "$2" ]; then
            echo "Usage: $0 iso <source_directory> [iso_name]"
            echo "Example: $0 iso /path/to/files transfer.iso"
        else
            create_transfer_iso "$2" "$3"
        fi
        ;;
    "rescue")
        create_rescue_script
        ;;
    "fat")
        create_fat_transfer "$2"
        ;;
    "show-vm-mod")
        show_vm_modification
        ;;
    "advanced")
        show_advanced_method
        ;;
    *)
        echo "File Transfer Methods for qcow2 Images (Container-Safe)"
        echo "======================================================="
        echo ""
        echo "Available methods:"
        echo "  $0 iso <dir>     - Create transfer ISO from directory"
        echo "  $0 rescue       - Create rescue boot script"
        echo "  $0 fat [size]    - Create FAT transfer image"
        echo "  $0 show-vm-mod   - Show how to modify VM script"
        echo "  $0 advanced      - Show advanced qemu-img method"
        echo ""
        echo "Recommended approach:"
        echo "1. Use '$0 iso /path/to/your/files' to create transfer.iso"
        echo "2. Modify your VM script to include the transfer ISO"
        echo "3. Boot Windows 98 and copy files from the ISO"
        ;;
esac
