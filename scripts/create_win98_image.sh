#!/usr/bin/env bash
# create_win98_image.sh -- Build QEMU container image and create/upload pre-built snapshots

# Exit immediately on errors and print a helpful message
set -euo pipefail
trap 'echo "ERROR: command failed on line $LINENO" >&2' ERR

# Configuration
REGISTRY=${REGISTRY:-ghcr.io/mroie}
QEMU_IMAGE=${QEMU_IMAGE:-qemu-loco}
SNAPSHOT_REGISTRY=${SNAPSHOT_REGISTRY:-ghcr.io/mroie/qemu-snapshots}
TAG=${TAG:-latest}
BUILD_SNAPSHOTS=${BUILD_SNAPSHOTS:-false}
PUSH_IMAGES=${PUSH_IMAGES:-true}
CLUSTER_NAME=${CLUSTER_NAME:-loco-cluster}

# Optional environment variable to capture verbose logs
LOG_FILE=${LOG_FILE:-create_win98_image.log}
exec > >(tee -i "$LOG_FILE") 2>&1

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --disk-image)
            SRC_DISK="$2"
            shift 2
            ;;
        --output-dir)
            OUT_DIR="$2"
            shift 2
            ;;
        --build-snapshots)
            BUILD_SNAPSHOTS=true
            shift
            ;;
        --no-push)
            PUSH_IMAGES=false
            shift
            ;;
        --registry)
            REGISTRY="$2"
            shift 2
            ;;
        --tag)
            TAG="$2"
            shift 2
            ;;
        --cluster)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --disk-image <path>     Source disk image to convert (optional)"
            echo "  --output-dir <path>     Output directory for images (default: ./images)"
            echo "  --build-snapshots       Build and upload pre-configured snapshots"
            echo "  --no-push              Don't push images to registry"
            echo "  --registry <url>        Container registry (default: ghcr.io/mroie)"
            echo "  --tag <tag>             Image tag (default: latest)"
            echo "  --cluster <name>        Kind cluster name (default: loco-cluster)"
            echo "  -h, --help              Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Set defaults
OUT_DIR=${OUT_DIR:-$(pwd)/images}
SRC_DISK=${SRC_DISK:-""}

echo "🏗️  QEMU Container Build Pipeline"
echo "==============================="
echo "Registry: $REGISTRY"
echo "QEMU Image: $QEMU_IMAGE:$TAG"
echo "Snapshot Registry: $SNAPSHOT_REGISTRY"
echo "Build Snapshots: $BUILD_SNAPSHOTS"
echo "Push Images: $PUSH_IMAGES"
echo "Output Directory: $OUT_DIR"
echo ""

# Ensure required tools are available
check_requirements() {
    local missing_tools=()
    
    if ! command -v docker >/dev/null; then
        missing_tools+=("docker")
    fi
    
    if ! command -v qemu-img >/dev/null; then
        missing_tools+=("qemu-img")
    fi
    
    if [[ "$PUSH_IMAGES" == "true" ]] && ! command -v skopeo >/dev/null; then
        echo "⚠️  Warning: skopeo not found. Pre-built snapshot downloading will not work."
    fi
    
    if [[ ${#missing_tools[@]} -ne 0 ]]; then
        echo "❌ Missing required tools: ${missing_tools[*]}" >&2
        exit 1
    fi
}

# Convert disk image if provided
convert_disk_image() {
    if [[ -n "$SRC_DISK" ]]; then
        if [[ ! -f "$SRC_DISK" ]]; then
            echo "❌ Source disk $SRC_DISK not found" >&2
            exit 1
        fi
        
        echo "💾 Converting disk image..."
        mkdir -p "$OUT_DIR"
        
        # Determine input format for qemu-img
        INPUT_FMT="raw"
        case "${SRC_DISK##*.}" in
            vhd|VHD)
                INPUT_FMT="vpc"
                ;;
            vmdk|VMDK)
                INPUT_FMT="vmdk"
                ;;
            qcow2|QCOW2)
                INPUT_FMT="qcow2"
                ;;
        esac
        
        RAW_OUT="$OUT_DIR/win98.img"
        QCOW_OUT="$OUT_DIR/win98.qcow2"
        
        echo "   Converting $SRC_DISK ($INPUT_FMT) to raw image: $RAW_OUT"
        qemu-img convert -f "$INPUT_FMT" -O raw "$SRC_DISK" "$RAW_OUT"
        
        echo "   Converting $SRC_DISK ($INPUT_FMT) to QCOW2 image: $QCOW_OUT"
        qemu-img convert -f "$INPUT_FMT" -O qcow2 "$SRC_DISK" "$QCOW_OUT"
        
        echo "✅ Disk images saved in $OUT_DIR"
    else
        echo "ℹ️  No disk image provided, using existing images in $OUT_DIR"
    fi
}

# Build QEMU container image
build_qemu_image() {
    echo ""
    echo "🐳 Building QEMU container image..."
    
    # Use relative path from the repository root
    local qemu_dir="containers/qemu"
    if [[ ! -d "$qemu_dir" ]]; then
        echo "❌ QEMU container directory not found: $qemu_dir" >&2
        echo "   Current directory: $(pwd)" >&2
        echo "   Available directories: $(ls -la)" >&2
        exit 1
    fi
    
    cd "$qemu_dir"
    
    echo "   Building ${REGISTRY}/${QEMU_IMAGE}:${TAG}..."
    docker build -t "${REGISTRY}/${QEMU_IMAGE}:${TAG}" .
    
    if [[ "$PUSH_IMAGES" == "true" ]]; then
        echo "   Pushing to registry..."
        docker push "${REGISTRY}/${QEMU_IMAGE}:${TAG}"
        echo "✅ QEMU image pushed to ${REGISTRY}/${QEMU_IMAGE}:${TAG}"
    else
        echo "✅ QEMU image built locally: ${REGISTRY}/${QEMU_IMAGE}:${TAG}"
    fi
}

# Load image into kind cluster
load_into_kind() {
    if command -v kind >/dev/null && kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        echo ""
        echo "📦 Loading image into kind cluster..."
        
        echo "   Loading ${REGISTRY}/${QEMU_IMAGE}:${TAG} into $CLUSTER_NAME..."
        kind load docker-image "${REGISTRY}/${QEMU_IMAGE}:${TAG}" --name "$CLUSTER_NAME"
        
        echo "✅ Image loaded into kind cluster"
    else
        echo "ℹ️  Kind cluster '$CLUSTER_NAME' not found, skipping image loading"
    fi
}

# Build pre-configured snapshots
build_snapshots() {
    if [[ "$BUILD_SNAPSHOTS" == "true" ]]; then
        echo ""
        echo "📸 Building pre-configured snapshots..."
        
        local base_image="$OUT_DIR/win98.qcow2"
        if [[ ! -f "$base_image" ]]; then
            echo "❌ Base QCOW2 image not found: $base_image" >&2
            echo "   Run with --disk-image to convert a disk image first" >&2
            exit 1
        fi
        
        # Create different snapshot variants
        local variants=("base" "games" "productivity")
        
        for variant in "${variants[@]}"; do
            echo "   Building snapshot variant: $variant"
            build_snapshot_variant "$variant" "$base_image"
        done
        
        echo "✅ All snapshot variants built successfully"
    else
        echo "ℹ️  Skipping snapshot building (use --build-snapshots to enable)"
    fi
}

# Build a specific snapshot variant
build_snapshot_variant() {
    local variant="$1"
    local base_image="$2"
    local work_dir="/tmp/snapshot-build-$variant"
    local snapshot_tag="win98-$variant"
    
    echo "     Creating $variant snapshot..."
    
    # Create work directory
    mkdir -p "$work_dir"
    cd "$work_dir"
    
    # Create working snapshot
    local work_snapshot="$work_dir/work_snapshot.qcow2"
    qemu-img create -f qcow2 -b "$base_image" "$work_snapshot"
    
    # For now, just convert the base image
    # In the future, this would start QEMU and install software
    local final_snapshot="$work_dir/snapshot.qcow2"
    qemu-img convert -f qcow2 -O qcow2 "$work_snapshot" "$final_snapshot"
    
    # Create container image with the snapshot
    cat > "$work_dir/Dockerfile" << EOF
FROM alpine:latest
RUN apk add --no-cache file
COPY snapshot.qcow2 /snapshot.qcow2
LABEL variant="$variant"
LABEL base-image="win98"
LABEL created="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
WORKDIR /
CMD ["sh", "-c", "echo 'Snapshot container for $variant variant' && ls -la /snapshot.qcow2 && file /snapshot.qcow2"]
EOF
    
    # Build and optionally push the snapshot container
    local snapshot_image="${SNAPSHOT_REGISTRY}:${snapshot_tag}"
    docker build -t "$snapshot_image" "$work_dir"
    
    if [[ "$PUSH_IMAGES" == "true" ]]; then
        docker push "$snapshot_image"
        echo "     ✅ Pushed $snapshot_image"
    else
        echo "     ✅ Built $snapshot_image locally"
    fi
    
    # Cleanup
    rm -rf "$work_dir"
}

# Main execution
main() {
    echo "🚀 Starting build process..."
    
    check_requirements
    convert_disk_image
    build_qemu_image
    load_into_kind
    build_snapshots
    
    echo ""
    echo "🎉 Build complete!"
    echo ""
    echo "Images built:"
    echo "  QEMU Container: ${REGISTRY}/${QEMU_IMAGE}:${TAG}"
    
    if [[ "$BUILD_SNAPSHOTS" == "true" ]]; then
        echo "  Snapshots:"
        echo "    ${SNAPSHOT_REGISTRY}:win98-base"
        echo "    ${SNAPSHOT_REGISTRY}:win98-games"
        echo "    ${SNAPSHOT_REGISTRY}:win98-productivity"
    fi
    
    if [[ "$PUSH_IMAGES" == "false" ]]; then
        echo ""
        echo "💡 Images are available locally. Use 'docker push' to upload to registry."
    fi
}

# Run main function
main "$@"
