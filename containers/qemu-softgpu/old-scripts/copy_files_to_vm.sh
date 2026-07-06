#!/bin/bash
# Script to copy files into Windows 98 qcow2 image using libguestfs-tools

set -e

IMAGE_PATH="../../images/win98.qcow2"
SOURCE_DIR="/path/to/your/files"  # Change this to your source directory
DEST_PATH="/Windows/Desktop"      # Change this to your destination path in Windows

echo "=== Method 1: Using virt-copy-in (Recommended) ==="
echo "Copy files into the VM image without starting it"
echo ""

# Example: Copy files to Windows Desktop
# virt-copy-in -a "$IMAGE_PATH" "$SOURCE_DIR"/* "$DEST_PATH"

echo "Usage examples:"
echo ""
echo "1. Copy a single file:"
echo "   virt-copy-in -a $IMAGE_PATH /host/path/file.txt /Windows/Desktop"
echo ""
echo "2. Copy multiple files:"
echo "   virt-copy-in -a $IMAGE_PATH /host/path/file1.txt /host/path/file2.exe /Windows/Desktop"
echo ""
echo "3. Copy a directory:"
echo "   virt-copy-in -a $IMAGE_PATH /host/path/directory /Windows"
echo ""
echo "4. List contents of the image first:"
echo "   virt-ls -a $IMAGE_PATH /"
echo ""
echo "5. Check filesystem info:"
echo "   virt-filesystems -a $IMAGE_PATH --long"
echo ""

echo "=== Method 2: Using guestfish (Interactive) ==="
echo "guestfish -a $IMAGE_PATH"
echo "Then use commands like:"
echo "  run"
echo "  list-filesystems"
echo "  mount /dev/sda1 /"
echo "  copy-in /host/file /destination"
echo ""

echo "=== Method 3: Using virt-customize ==="
echo "virt-customize -a $IMAGE_PATH --copy-in /host/path:/dest/path"
echo ""

echo "=== Method 4: NBD (Network Block Device) Mount (RECOMMENDED for containers) ==="
echo "# This method works best in container environments"
echo "sudo modprobe nbd max_part=8"
echo "sudo qemu-nbd --connect=/dev/nbd0 $IMAGE_PATH"
echo "sudo fdisk -l /dev/nbd0  # Check partitions"
echo "sudo mount /dev/nbd0p1 /mnt"
echo "# Copy files to /mnt"
echo "sudo umount /mnt"
echo "sudo qemu-nbd --disconnect /dev/nbd0"
echo ""

echo "=== Method 5: Direct QEMU mounting (Alternative) ==="
echo "# Create a temporary directory"
echo "mkdir -p /tmp/vm_mount"
echo "# Use qemu-nbd to expose the image as a block device"
echo "sudo qemu-nbd -c /dev/nbd0 $IMAGE_PATH"
echo "# Mount the Windows partition (usually the first one)"
echo "sudo mount -t ntfs /dev/nbd0p1 /tmp/vm_mount"
echo "# Copy your files"
echo "sudo cp /path/to/your/files/* /tmp/vm_mount/"
echo "# Unmount and disconnect"
echo "sudo umount /tmp/vm_mount"
echo "sudo qemu-nbd -d /dev/nbd0"
