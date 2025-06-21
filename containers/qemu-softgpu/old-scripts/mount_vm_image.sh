#!/bin/bash
# Practical script to mount and copy files to Windows 98 qcow2 image
# This works in container environments where libguestfs may not work

set -e

IMAGE_PATH="../../images/win98.qcow2"
MOUNT_POINT="/tmp/win98_mount"

# Function to show usage
show_usage() {
    echo "Usage: $0 [mount|umount|copy|status]"
    echo ""
    echo "Commands:"
    echo "  mount   - Mount the VM image"
    echo "  umount  - Unmount the VM image"
    echo "  copy    - Copy files to the mounted image"
    echo "  status  - Check if image is mounted"
    echo ""
    echo "Examples:"
    echo "  $0 mount"
    echo "  $0 copy /path/to/file.exe"
    echo "  $0 umount"
}

# Function to check if NBD module is loaded
check_nbd() {
    if ! lsmod | grep -q nbd; then
        echo "Loading NBD kernel module..."
        sudo modprobe nbd max_part=8 || {
            echo "Error: Could not load NBD module. You may need to run this on the host system."
            exit 1
        }
    fi
}

# Function to mount the image
mount_image() {
    check_nbd
    
    if [ -b /dev/nbd0 ] && sudo qemu-nbd --list | grep -q /dev/nbd0; then
        echo "NBD device already in use. Trying to disconnect first..."
        sudo qemu-nbd --disconnect /dev/nbd0 || true
        sleep 1
    fi
    
    echo "Connecting qcow2 image to NBD device..."
    sudo qemu-nbd --connect=/dev/nbd0 "$IMAGE_PATH" || {
        echo "Error: Could not connect image to NBD device"
        exit 1
    }
    
    # Wait a moment for the device to be ready
    sleep 2
    
    echo "Checking partitions..."
    sudo fdisk -l /dev/nbd0
    
    echo "Creating mount point..."
    sudo mkdir -p "$MOUNT_POINT"
    
    # Try to mount the first partition (usually where Windows is installed)
    echo "Mounting Windows partition..."
    if sudo mount -t ntfs-3g /dev/nbd0p1 "$MOUNT_POINT" 2>/dev/null; then
        echo "Mounted as NTFS"
    elif sudo mount -t vfat /dev/nbd0p1 "$MOUNT_POINT" 2>/dev/null; then
        echo "Mounted as FAT"
    else
        echo "Trying to mount without specifying filesystem type..."
        sudo mount /dev/nbd0p1 "$MOUNT_POINT" || {
            echo "Error: Could not mount partition. The image may not be formatted yet."
            sudo qemu-nbd --disconnect /dev/nbd0
            exit 1
        }
    fi
    
    echo "Successfully mounted at $MOUNT_POINT"
    echo "Contents:"
    sudo ls -la "$MOUNT_POINT"
}

# Function to unmount the image
umount_image() {
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        echo "Unmounting $MOUNT_POINT..."
        sudo umount "$MOUNT_POINT"
    fi
    
    if [ -b /dev/nbd0 ]; then
        echo "Disconnecting NBD device..."
        sudo qemu-nbd --disconnect /dev/nbd0
    fi
    
    echo "Image unmounted successfully"
}

# Function to copy files
copy_files() {
    if [ $# -eq 0 ]; then
        echo "Usage: $0 copy <source_file_or_directory> [destination_path]"
        echo "Example: $0 copy /path/to/game.exe Windows/Desktop/"
        return 1
    fi
    
    SOURCE="$1"
    DEST="${2:-}"
    
    if ! mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        echo "Image not mounted. Mounting first..."
        mount_image
    fi
    
    if [ -z "$DEST" ]; then
        # Copy to root of mounted filesystem
        TARGET_PATH="$MOUNT_POINT/"
    else
        # Copy to specified subdirectory
        TARGET_PATH="$MOUNT_POINT/$DEST"
        sudo mkdir -p "$TARGET_PATH"
    fi
    
    echo "Copying $SOURCE to $TARGET_PATH..."
    sudo cp -r "$SOURCE" "$TARGET_PATH"
    
    echo "Copy completed. Files in destination:"
    sudo ls -la "$TARGET_PATH"
}

# Function to check status
check_status() {
    echo "=== Mount Status ==="
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        echo "✓ Image is mounted at $MOUNT_POINT"
        echo "Contents:"
        sudo ls -la "$MOUNT_POINT" | head -10
    else
        echo "✗ Image is not mounted"
    fi
    
    echo ""
    echo "=== NBD Status ==="
    if lsmod | grep -q nbd; then
        echo "✓ NBD module is loaded"
        if [ -b /dev/nbd0 ]; then
            echo "✓ NBD device /dev/nbd0 exists"
        else
            echo "✗ NBD device /dev/nbd0 not found"
        fi
    else
        echo "✗ NBD module not loaded"
    fi
}

# Main script logic
case "${1:-}" in
    mount)
        mount_image
        ;;
    umount)
        umount_image
        ;;
    copy)
        shift
        copy_files "$@"
        ;;
    status)
        check_status
        ;;
    *)
        show_usage
        exit 1
        ;;
esac
