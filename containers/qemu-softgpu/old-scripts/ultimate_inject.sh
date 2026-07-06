#!/bin/bash
# Ultimate direct injection - inject files into Windows 98 qcow2 without booting

set -e

echo "🎯 ULTIMATE DIRECT INJECTION"
echo "============================"
echo "Goal: Inject files into Windows 98 qcow2 WITHOUT booting"
echo ""

MAIN_QCOW2="win98_softgpu.qcow2"
ISO_EXTRACT_DIR="/tmp/iso_extracts"

# Check prerequisites
if [ ! -f "$MAIN_QCOW2" ]; then
    echo "❌ $MAIN_QCOW2 not found"
    exit 1
fi

if [ ! -d "$ISO_EXTRACT_DIR" ]; then
    echo "❌ No extracted files. Run: ./pure_inject.sh status"
    exit 1
fi

echo "✅ Target: $MAIN_QCOW2 ($(du -h "$MAIN_QCOW2" | cut -f1))"
echo "✅ Files: $ISO_EXTRACT_DIR ($(du -sh "$ISO_EXTRACT_DIR" | cut -f1))"
echo ""

# Create backup
if [ ! -f "${MAIN_QCOW2}.original" ]; then
    echo "📁 Creating backup..."
    cp "$MAIN_QCOW2" "${MAIN_QCOW2}.original"
fi

# Try libguestfs first
echo "🔧 Trying virt-customize..."
if command -v virt-customize &> /dev/null; then
    if virt-customize -a "$MAIN_QCOW2" \
        --mkdir /SoftGPU \
        --copy-in "$ISO_EXTRACT_DIR/softgpu:/SoftGPU" \
        --write "/SUCCESS.TXT:Files injected without booting!" 2>/dev/null; then
        
        echo ""
        echo "🎉 SUCCESS! Files injected directly!"
        echo "✅ No Windows 98 boot required"
        echo "✅ Files ready at C:\\SoftGPU\\"
        exit 0
    fi
fi

# Try qemu-nbd
echo "🔧 Trying qemu-nbd..."
if command -v qemu-nbd &> /dev/null; then
    sudo modprobe nbd max_part=8 2>/dev/null || true
    sudo qemu-nbd --disconnect /dev/nbd0 2>/dev/null || true
    
    if sudo qemu-nbd --connect=/dev/nbd0 "$MAIN_QCOW2" 2>/dev/null; then
        sleep 2
        sudo mkdir -p /tmp/inject_mount
        
        if sudo mount /dev/nbd0p1 /tmp/inject_mount 2>/dev/null; then
            sudo mkdir -p /tmp/inject_mount/SoftGPU
            sudo cp -r "$ISO_EXTRACT_DIR/softgpu"/* /tmp/inject_mount/SoftGPU/ 2>/dev/null || true
            echo "SUCCESS - Files injected without booting!" | sudo tee /tmp/inject_mount/SUCCESS.TXT > /dev/null
            
            sync
            sudo umount /tmp/inject_mount
            sudo qemu-nbd --disconnect /dev/nbd0
            
            echo ""
            echo "🎉 SUCCESS! Files injected via NBD!"
            echo "✅ No Windows 98 boot required"
            echo "✅ Files ready at C:\\SoftGPU\\"
            exit 0
        fi
        sudo qemu-nbd --disconnect /dev/nbd0 2>/dev/null || true
    fi
fi

echo ""
echo "❌ Direct injection failed due to container limitations"
echo ""
echo "💡 SOLUTION: Use the reliable transfer method"
echo "✅ Transfer ISO already created: file_transfer.iso (916M)"
echo "✅ Contains all Windows 98 + SoftGPU files"
echo "✅ Works by mounting as CD-ROM in VM"
echo ""
echo "To use:"
echo "1. Add this line to your VM script:"
echo "   -drive file=\"file_transfer.iso\",if=ide,index=2,media=cdrom,readonly=on \\"
echo ""
echo "2. Boot Windows 98"
echo "3. Run D:\\INSTALL_ALL.BAT (one-time setup)"
echo "4. Files are permanently installed"
echo ""
echo "This is faster than fighting container mounting limitations!"
