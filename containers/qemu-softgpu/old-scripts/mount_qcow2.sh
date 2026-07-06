#!/bin/bash
# Script to safely mount qcow2 images using loop devices
# Handles cleanup and finds available loop devices automatically

set -e

IMAGE_PATH="../../images/win98.qcow2"
RAW_IMAGE="win98softgpu.raw"
MOUNT_POINT="/tmp/win98_mount"

# Function to show usage
show_usage() {
    echo "Usage: $0 [mount|umount|copy|status|cleanup]"
    echo ""
    echo "Commands:"
    echo "  mount   - Convert qcow2 to raw and mount"
    echo "  umount  - Unmount and cleanup"
    echo "  copy    - Copy files to mounted image"
    echo "  status  - Show current mount status"
    echo "  cleanup - Force cleanup of loop devices and temp files"
    echo ""
    echo "Examples:"
    echo "  $0 mount"
    echo "  $0 copy /path/to/file.exe Windows/Desktop/"
    echo "  $0 umount"
}

# Function to cleanup loop devices
cleanup_loops() {
    echo "Cleaning up loop devices..."
    
    # Find all loop devices associated with our raw image
    for loop in $(losetup -a | grep "$RAW_IMAGE" | cut -d: -f1); do
        echo "Detaching $loop..."
        sudo losetup -d "$loop" || true
    done
    
    # Check for any mounts using our mount point
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        echo "Unmounting $MOUNT_POINT..."
        sudo umount "$MOUNT_POINT" || true
    fi
    
    # Remove raw image if it exists
    if [ -f "$RAW_IMAGE" ]; then
        echo "Removing temporary raw image..."
        rm -f "$RAW_IMAGE"
    fi
    
    echo "Cleanup completed"
}

# Function to find available loop device
find_loop_device() {
    # Try to find an unused loop device
    for i in {0..15}; do
        if ! losetup -a | grep -q "/dev/loop$i"; then
            echo "/dev/loop$i"
            return 0
        fi
    done
    
    # If no free loop device found, try to create one
    echo "No free loop devices found, trying to create one..."
    sudo mknod /dev/loop16 b 7 16 2>/dev/null || true
    echo "/dev/loop16"
}

# Function to convert and mount
mount_image() {
    echo "=== Mounting qcow2 image ==="
    
    # Cleanup first
    cleanup_loops
    
    # Check if qcow2 image exists
    if [ ! -f "$IMAGE_PATH" ]; then
        echo "Error: qcow2 image not found at $IMAGE_PATH"
        exit 1
    fi
    
    echo "Converting qcow2 to raw format..."
    qemu-img convert -f qcow2 -O raw "$IMAGE_PATH" "$RAW_IMAGE"
    
    echo "Finding available loop device..."
    LOOP_DEVICE=$(find_loop_device)
    echo "Using loop device: $LOOP_DEVICE"
    
    echo "Setting up loop device..."
    sudo losetup "$LOOP_DEVICE" "$RAW_IMAGE"
    
    # Wait a moment for the device to be ready
    sleep 1
    
    # Check partitions
    echo "Checking partitions..."
    sudo fdisk -l "$LOOP_DEVICE" || true
    
    # Create mount point
    sudo mkdir -p "$MOUNT_POINT"
    
    # Try to mount the first partition
    echo "Attempting to mount partition..."
    PARTITION="${LOOP_DEVICE}p1"
    
    # If partition doesn't exist, try the whole device
    if [ ! -b "$PARTITION" ]; then
        echo "Partition $PARTITION not found, trying whole device..."
        PARTITION="$LOOP_DEVICE"
    fi
    
    # Try different filesystem types
    if sudo mount -t ntfs-3g "$PARTITION" "$MOUNT_POINT" 2>/dev/null; then
        echo "✓ Mounted as NTFS at $MOUNT_POINT"
    elif sudo mount -t vfat "$PARTITION" "$MOUNT_POINT" 2>/dev/null; then
        echo "✓ Mounted as FAT at $MOUNT_POINT"
    elif sudo mount "$PARTITION" "$MOUNT_POINT" 2>/dev/null; then
        echo "✓ Mounted (auto-detected filesystem) at $MOUNT_POINT"
    else
        echo "❌ Failed to mount. The image might not be formatted yet."
        echo "You may need to install Windows 98 first before you can mount it."
        cleanup_loops
        exit 1
    fi
    
    echo ""
    echo "=== Mount successful! ==="
    echo "Contents of mounted image:"
    sudo ls -la "$MOUNT_POINT" | head -10
    echo ""
    echo "You can now copy files to $MOUNT_POINT"
    echo "Use '$0 umount' when finished"
}

# Function to unmount
umount_image() {
    echo "=== Unmounting image ==="
    cleanup_loops
    echo "✓ Image unmounted successfully"
}

# Function to copy files
copy_files() {
    if [ $# -eq 0 ]; then
        echo "Usage: $0 copy <source> [destination_path_in_image]"
        echo "Examples:"
        echo "  $0 copy /path/to/game.exe"
        echo "  $0 copy /path/to/files/ Windows/Desktop/"
        return 1
    fi
    
    SOURCE="$1"
    DEST="${2:-.}"  # Default to root if no destination specified
    
    if ! mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        echo "Image not mounted. Mounting first..."
        mount_image
    fi
    
    TARGET_PATH="$MOUNT_POINT/$DEST"
    
    # Create destination directory if it doesn't exist
    if [[ "$DEST" != "." && ! -d "$TARGET_PATH" ]]; then
        echo "Creating destination directory: $DEST"
        sudo mkdir -p "$TARGET_PATH"
    fi
    
    echo "Copying $SOURCE to $TARGET_PATH..."
    if [ -d "$SOURCE" ]; then
        sudo cp -r "$SOURCE"/* "$TARGET_PATH/"
    else
        sudo cp "$SOURCE" "$TARGET_PATH/"
    fi
    
    echo "✓ Copy completed successfully"
    echo "Files in destination:"
    sudo ls -la "$TARGET_PATH" | tail -5
}

# Function to show status
show_status() {
    echo "=== Mount Status ==="
    
    if [ -f "$RAW_IMAGE" ]; then
        echo "✓ Raw image exists: $RAW_IMAGE"
    else
        echo "✗ Raw image not found: $RAW_IMAGE"
    fi
    
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        echo "✓ Image is mounted at $MOUNT_POINT"
        echo "Mount details:"
        mount | grep "$MOUNT_POINT"
        echo ""
        echo "Available space:"
        df -h "$MOUNT_POINT"
    else
        echo "✗ Image is not mounted"
    fi
    
    echo ""
    echo "=== Loop Devices ==="
    losetup -a | grep "$RAW_IMAGE" || echo "No loop devices found for $RAW_IMAGE"
}

# Main script
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
        show_status
        ;;
    cleanup)
        cleanup_loops
        ;;
    *)
        show_usage
        exit 1
        ;;
esac
