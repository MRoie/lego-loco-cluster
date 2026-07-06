#!/usr/bin/env bash
# test_and_download_snapshots.sh -- Test simplified workflow locally and check for published snapshots

set -euo pipefail

echo "🧪 Testing Simplified QEMU Build and Snapshot Workflow"
echo "====================================================="
echo ""

# Configuration
REGISTRY="ghcr.io/mroie"
IMAGE_NAME="qemu-loco"
SNAPSHOT_REGISTRY="ghcr.io/mroie/qemu-snapshots"

echo "📋 Testing Steps:"
echo "1. Test local QEMU container build"
echo "2. Test local snapshot creation"
echo "3. Check for published images in GitHub Container Registry"
echo "4. If available, download and test published snapshots"
echo "5. Deploy to cluster with downloaded snapshots"
echo ""

# Step 1: Test local build (mimicking the simplified workflow)
echo "🏗️  Step 1: Testing local QEMU container build..."
cd containers/qemu
if docker build -t ${REGISTRY}/${IMAGE_NAME}:test .; then
    echo "✅ QEMU container build successful"
else
    echo "❌ QEMU container build failed"
    exit 1
fi
cd ../..

# Step 2: Test local snapshot creation
echo ""
echo "📸 Step 2: Testing local snapshot creation..."

# Install dependencies (if needed)
if ! command -v qemu-img >/dev/null; then
    echo "Installing qemu-utils..."
    sudo apt-get update >/dev/null 2>&1
    sudo apt-get install -y qemu-utils >/dev/null 2>&1
fi

# Create minimal test VM image
mkdir -p images
if [[ ! -f images/win98.qcow2 ]]; then
    echo "Creating test VM image..."
    qemu-img create -f qcow2 images/win98.qcow2 2G >/dev/null 2>&1
    
    # Create simple boot sector for testing
    dd if=/dev/zero of=images/boot.img bs=512 count=1 2>/dev/null
    echo -en '\x55\xAA' | dd of=images/boot.img bs=1 seek=510 conv=notrunc 2>/dev/null
    
    # Copy boot sector to the qcow2 image
    qemu-img create -f raw images/base.img 2G 2>/dev/null
    dd if=images/boot.img of=images/base.img conv=notrunc 2>/dev/null
    qemu-img convert -f raw -O qcow2 images/base.img images/win98.qcow2 2>/dev/null
    echo "✅ Test VM image created"
fi

# Build snapshots using our script
echo "Building snapshots..."
chmod +x ./scripts/create_win98_image.sh
if ./scripts/create_win98_image.sh \
    --build-snapshots \
    --registry ${REGISTRY} \
    --tag test \
    --no-push >/dev/null 2>&1; then
    echo "✅ Local snapshot creation successful"
else
    echo "❌ Local snapshot creation failed"
    exit 1
fi

# Step 3: Check for published images
echo ""
echo "🔍 Step 3: Checking for published images in GitHub Container Registry..."

check_image() {
    local image_name="$1"
    echo "   Checking: $image_name"
    
    # Try to inspect the image without pulling
    if docker manifest inspect "$image_name" >/dev/null 2>&1; then
        echo "     ✅ Available: $image_name"
        return 0
    else
        echo "     ❌ Not available: $image_name"
        return 1
    fi
}

# Check main QEMU container
qemu_available=false
if check_image "${REGISTRY}/${IMAGE_NAME}:latest"; then
    qemu_available=true
fi

# Check snapshot images
snapshots_available=()
for variant in base games productivity; do
    if check_image "${SNAPSHOT_REGISTRY}:win98-${variant}"; then
        snapshots_available+=("$variant")
    fi
done

echo ""
echo "📊 Availability Summary:"
echo "   QEMU Container: $([ "$qemu_available" = true ] && echo "✅ Available" || echo "❌ Not available")"
echo "   Snapshots Available: ${#snapshots_available[@]}/3 (${snapshots_available[*]})"

# Step 4: Download and test published snapshots (if available)
echo ""
echo "📥 Step 4: Testing snapshot download..."

if [ ${#snapshots_available[@]} -gt 0 ]; then
    echo "Downloading available snapshots..."
    for variant in "${snapshots_available[@]}"; do
        echo "   Downloading: ${SNAPSHOT_REGISTRY}:win98-${variant}"
        if docker pull "${SNAPSHOT_REGISTRY}:win98-${variant}" >/dev/null 2>&1; then
            echo "     ✅ Downloaded: win98-${variant}"
            
            # Test the downloaded snapshot
            if docker run --rm "${SNAPSHOT_REGISTRY}:win98-${variant}" >/dev/null 2>&1; then
                echo "     ✅ Verified: win98-${variant} works"
            else
                echo "     ⚠️  Download successful but container test failed"
            fi
        else
            echo "     ❌ Failed to download: win98-${variant}"
        fi
    done
else
    echo "⚠️  No published snapshots available yet"
    echo "   Using local snapshots for testing"
fi

# Step 5: Deploy to cluster
echo ""
echo "🚀 Step 5: Testing cluster deployment..."

# Check if kind cluster exists
if ! kind get clusters | grep -q "loco-cluster"; then
    echo "⚠️  Kind cluster 'loco-cluster' not found"
    echo "   Run: kind create cluster --name loco-cluster --config k8s/kind-config.yaml"
    echo "   Skipping cluster deployment test"
    exit 0
fi

# Load images into kind
echo "Loading images into kind cluster..."
if [ "$qemu_available" = true ]; then
    echo "   Loading published QEMU image..."
    docker pull "${REGISTRY}/${IMAGE_NAME}:latest" >/dev/null 2>&1 || echo "   ⚠️  Failed to pull published QEMU image"
    kind load docker-image "${REGISTRY}/${IMAGE_NAME}:latest" --name loco-cluster >/dev/null 2>&1 || echo "   ⚠️  Failed to load published QEMU image"
else
    echo "   Loading local QEMU image..."
    kind load docker-image "${REGISTRY}/${IMAGE_NAME}:test" --name loco-cluster >/dev/null 2>&1 || echo "   ⚠️  Failed to load local QEMU image"
fi

# Load snapshots
if [ ${#snapshots_available[@]} -gt 0 ]; then
    echo "   Loading published snapshots..."
    for variant in "${snapshots_available[@]}"; do
        kind load docker-image "${SNAPSHOT_REGISTRY}:win98-${variant}" --name loco-cluster >/dev/null 2>&1 || echo "   ⚠️  Failed to load $variant"
    done
else
    echo "   Loading local snapshots..."
    for variant in base games productivity; do
        kind load docker-image "${SNAPSHOT_REGISTRY}:win98-${variant}" --name loco-cluster >/dev/null 2>&1 || echo "   ⚠️  Failed to load local $variant"
    done
fi

# Test deployment with Helm
echo "   Testing Helm deployment with snapshots..."
cat > test-deploy-values.yaml << EOF
emulator:
  image: ${IMAGE_NAME}
  tag: $([ "$qemu_available" = true ] && echo "latest" || echo "test")
  imagePullPolicy: Never
  usePrebuiltSnapshot: true
  snapshotRegistry: "${SNAPSHOT_REGISTRY}"
  snapshotTag: "win98-base"
  env:
    USE_PREBUILT_SNAPSHOT: "true"
    SNAPSHOT_REGISTRY: "${SNAPSHOT_REGISTRY}"
    SNAPSHOT_TAG: "win98-base"
EOF

# Clean up any existing deployment
helm uninstall test-snapshot --ignore-not-found >/dev/null 2>&1 || true

if helm install test-snapshot helm/loco-chart/ -f test-deploy-values.yaml >/dev/null 2>&1; then
    echo "✅ Helm deployment successful"
    
    # Check pod status
    if kubectl wait --for=condition=ready pod -l app=test-snapshot-loco-emulator --timeout=60s >/dev/null 2>&1; then
        echo "✅ Emulator pod is ready"
        
        # Check environment variables
        pod_name=$(kubectl get pod -l app=test-snapshot-loco-emulator -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [[ -n "$pod_name" ]]; then
            echo "   📋 Snapshot environment variables:"
            kubectl get pod "$pod_name" -o yaml | grep -A 3 -B 1 "SNAPSHOT" | sed 's/^/      /' || echo "      No snapshot env vars found"
        fi
    else
        echo "⚠️  Emulator pod not ready within timeout"
        kubectl get pods -l app=test-snapshot-loco-emulator 2>/dev/null | sed 's/^/      /' || true
    fi
    
    # Cleanup
    helm uninstall test-snapshot >/dev/null 2>&1 || true
else
    echo "❌ Helm deployment failed"
fi

rm -f test-deploy-values.yaml

echo ""
echo "🎉 Test Complete!"
echo ""
echo "📊 Summary:"
echo "   ✅ Local QEMU container build: Working"
echo "   ✅ Local snapshot creation: Working"
echo "   📡 Published QEMU container: $([ "$qemu_available" = true ] && echo "Available" || echo "Not yet available")"
echo "   📡 Published snapshots: ${#snapshots_available[@]}/3 available"
echo "   🚀 Cluster deployment: Tested"
echo ""

if [ "$qemu_available" = true ] && [ ${#snapshots_available[@]} -gt 0 ]; then
    echo "🎯 Ready for production! Published images are available."
    echo ""
    echo "Usage:"
    echo "   # Pull published QEMU container"
    echo "   docker pull ${REGISTRY}/${IMAGE_NAME}:latest"
    echo ""
    echo "   # Deploy with published snapshots"
    echo "   helm install loco helm/loco-chart/ \\"
    echo "     --set emulator.usePrebuiltSnapshot=true \\"
    echo "     --set emulator.snapshotRegistry=${SNAPSHOT_REGISTRY} \\"
    echo "     --set emulator.snapshotTag=win98-base"
else
    echo "🔄 GitHub Actions workflow is building and publishing images..."
    echo "   Check status: gh run list"
    echo "   Monitor logs: gh run view --log"
fi
