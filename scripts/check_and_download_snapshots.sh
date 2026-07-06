#!/usr/bin/env bash
# check_and_download_snapshots.sh -- Check for new snapshots and download them

set -euo pipefail

echo "🔍 Checking for New Snapshots and Images"
echo "========================================"

# Configuration
REGISTRY=${REGISTRY:-ghcr.io/mroie}
QEMU_IMAGE=${QEMU_IMAGE:-qemu-loco}
SNAPSHOT_REGISTRY=${SNAPSHOT_REGISTRY:-ghcr.io/mroie/qemu-snapshots}
CLUSTER_NAME=${CLUSTER_NAME:-loco-cluster}

echo "Registry: $REGISTRY"
echo "QEMU Image: $QEMU_IMAGE"
echo "Snapshot Registry: $SNAPSHOT_REGISTRY"
echo ""

# Function to check if image exists
check_image_exists() {
    local image="$1"
    echo "🔎 Checking if $image exists..."
    if docker manifest inspect "$image" >/dev/null 2>&1; then
        echo "✅ Image found: $image"
        return 0
    else
        echo "❌ Image not found: $image"
        return 1
    fi
}

# Function to pull and load image into kind
pull_and_load_image() {
    local image="$1"
    echo "📥 Pulling $image..."
    if docker pull "$image"; then
        echo "✅ Successfully pulled $image"
        
        # Load into kind cluster if available
        if command -v kind >/dev/null && kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
            echo "📦 Loading $image into Kind cluster $CLUSTER_NAME..."
            kind load docker-image "$image" --name "$CLUSTER_NAME"
            echo "✅ Loaded into Kind cluster"
        else
            echo "⚠️  Kind cluster $CLUSTER_NAME not found, skipping cluster loading"
        fi
        return 0
    else
        echo "❌ Failed to pull $image"
        return 1
    fi
}

# Check current workflow status
echo "🚀 Checking GitHub Actions Status"
echo "--------------------------------"
echo "Recent workflow runs:"
gh run list --limit 5 --json databaseId,conclusion,workflowName,headBranch,createdAt | jq -r '.[] | "\(.workflowName): \(.conclusion // "running") (\(.createdAt))"'

echo ""

# Check for QEMU main image
echo "🐳 Checking QEMU Container Images"
echo "--------------------------------"
qemu_images=("${REGISTRY}/${QEMU_IMAGE}:latest" "${REGISTRY}/${QEMU_IMAGE}:v1.0.0")

for image in "${qemu_images[@]}"; do
    if check_image_exists "$image"; then
        pull_and_load_image "$image" || echo "Failed to pull $image"
    fi
done

echo ""

# Check for snapshot images
echo "📸 Checking Snapshot Images"
echo "---------------------------"
snapshot_variants=("base" "games" "productivity")

for variant in "${snapshot_variants[@]}"; do
    snapshot_image="${SNAPSHOT_REGISTRY}:win98-${variant}"
    if check_image_exists "$snapshot_image"; then
        pull_and_load_image "$snapshot_image" || echo "Failed to pull $snapshot_image"
    fi
done

echo ""

# Test snapshot functionality if images are available
echo "🧪 Testing Snapshot Functionality"
echo "--------------------------------"

# Check if we have any snapshot images locally
local_snapshots=$(docker images --format "table {{.Repository}}:{{.Tag}}" | grep "qemu-snapshots" || echo "")

if [[ -n "$local_snapshots" ]]; then
    echo "✅ Found local snapshot images:"
    echo "$local_snapshots"
    echo ""
    
    # Test one of the snapshots
    test_image=$(echo "$local_snapshots" | head -1 | tr -d ' ')
    echo "🔬 Testing snapshot image: $test_image"
    
    if docker run --rm "$test_image" && echo "✅ Snapshot container test passed"; then
        echo "✅ Snapshot functionality verified"
    else
        echo "❌ Snapshot container test failed"
    fi
else
    echo "⚠️  No snapshot images found locally yet"
fi

echo ""

# Update cluster with new images if available
echo "🔄 Updating Cluster"
echo "------------------"

# Check if we can update any existing deployments
if kubectl get deployments 2>/dev/null | grep -q loco; then
    echo "Found existing loco deployments:"
    kubectl get deployments | grep loco
    
    # Update deployment images if new ones are available
    latest_qemu_image="${REGISTRY}/${QEMU_IMAGE}:latest"
    if docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "${REGISTRY}/${QEMU_IMAGE}:latest"; then
        echo "🔄 Updating deployment with new QEMU image..."
        # kubectl set image deployment/loco-emulator emulator="$latest_qemu_image" || echo "No deployment to update"
        echo "   To update: kubectl set image deployment/loco-emulator emulator=$latest_qemu_image"
    fi
else
    echo "⚠️  No existing loco deployments found"
    echo "   To deploy with snapshots:"
    echo "   helm install loco helm/loco-chart/ --set emulator.usePrebuiltSnapshot=true"
fi

echo ""
echo "📊 Summary"
echo "----------"
echo "Images checked:"
for image in "${qemu_images[@]}"; do
    if docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "$image"; then
        echo "  ✅ $image (available locally)"
    else
        echo "  ❌ $image (not available)"
    fi
done

echo "Snapshots checked:"
for variant in "${snapshot_variants[@]}"; do
    snapshot_image="${SNAPSHOT_REGISTRY}:win98-${variant}"
    if docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "$snapshot_image"; then
        echo "  ✅ $snapshot_image (available locally)"
    else
        echo "  ❌ $snapshot_image (not available)"
    fi
done

echo ""
echo "🎯 Next Steps:"
echo "1. Monitor GitHub Actions: gh run watch"
echo "2. Check logs if builds fail: gh run view --log-failed"
echo "3. Deploy with snapshots: helm install loco helm/loco-chart/ --set emulator.usePrebuiltSnapshot=true"
