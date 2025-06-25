#!/usr/bin/env bash
set -euo pipefail

# Configuration
SNAPSHOT_REGISTRY=${SNAPSHOT_REGISTRY:-ghcr.io/mroie/qemu-snapshots}
SNAPSHOT_TAG=${SNAPSHOT_TAG:-win98-loco}
BASE_IMAGE=${BASE_IMAGE:-/workspaces/lego-loco-cluster/containers/qemu-softgpu/win98_softgpu.qcow2}
BIOS_BIN=${BIOS_BIN:-/workspaces/lego-loco-cluster/containers/qemu-softgpu/bios.bin}
WORK_DIR=${WORK_DIR:-/tmp/snapshot-build}

echo "🏗️  Building pre-configured snapshot..."
echo "   Registry: $SNAPSHOT_REGISTRY"
echo "   Tag: $SNAPSHOT_TAG"
echo "   Base Image: $BASE_IMAGE"

# Check if base image exists
if [ ! -f "$BASE_IMAGE" ]; then
    echo "❌ Base image not found: $BASE_IMAGE"
    exit 1
fi

# Create work directory
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Create a working snapshot
WORK_SNAPSHOT="$WORK_DIR/work_snapshot.qcow2"
echo "📀 Creating working snapshot..."
qemu-img create -f qcow2 -b "$BASE_IMAGE" "$WORK_SNAPSHOT"

# Start QEMU in background for configuration
echo "🚀 Starting QEMU for configuration..."
-enable-kvm \
        -m 768 \
        -cpu pentium3 \
        -smp 1 \
        -bios "$BIOS_BIN" \
        -hda "$QCOW2_IMAGE" \
        -machine pc-i440fx-2.12 \
        -boot order=c,menu=on \
        -vga std \
        -rtc base=localtime \
        -netdev tap,id=net0,ifname=tap0,script=no,downscript=no \
        -device ne2k_pci,netdev=net0 \
        -audiodev pa,id=snd0 \
        -device sb16,audiodev=snd0 \
        -usb \
        -device usb-tablet \
        -name "Loco" \
        -vnc 0.0.0.0:0 

QEMU_PID=$!

echo "⏱️  Waiting for Windows 98 to boot (this may take several minutes)..."
sleep 180  # Give it time to boot

# You could add automation here to:
# 1. Install software via monitor commands
# 2. Configure settings
# 3. Install drivers
# 4. Set up applications

echo "💾 Creating final snapshot..."
# Send shutdown command via monitor
echo "system_powerdown" | nc 127.0.0.1 4444 || true
sleep 10

# Wait for QEMU to exit
kill $QEMU_PID 2>/dev/null || true
wait $QEMU_PID 2>/dev/null || true

# Commit the changes to a final snapshot
FINAL_SNAPSHOT="$WORK_DIR/snapshot.qcow2"
qemu-img convert -f qcow2 -O qcow2 "$WORK_SNAPSHOT" "$FINAL_SNAPSHOT"

# Create container image with the snapshot
echo "📦 Creating container image..."
cat > "$WORK_DIR/Dockerfile" << EOF
FROM scratch
COPY snapshot.qcow2 /snapshot.qcow2
EOF

# Build and push the snapshot container
docker build -t "${SNAPSHOT_REGISTRY}:${SNAPSHOT_TAG}" "$WORK_DIR"

echo "📤 Pushing snapshot to registry..."
docker push "${SNAPSHOT_REGISTRY}:${SNAPSHOT_TAG}"

echo "✅ Snapshot built and published successfully!"
echo "   Image: ${SNAPSHOT_REGISTRY}:${SNAPSHOT_TAG}"

# Cleanup
rm -rf "$WORK_DIR"
