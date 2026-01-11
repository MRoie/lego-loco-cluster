#!/usr/bin/env bash
set -euo pipefail

# Enhanced logging function
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log_error() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ❌ ERROR: $1" >&2
}

log_success() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ✅ SUCCESS: $1"
}

log_info() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ℹ️  INFO: $1"
}

if [ "$#" -ne 2 ]; then
    log_error "Usage: $0 <SNAPSHOT_URL> <TARGET_FILE>"
    exit 1
fi

SNAPSHOT_URL="$1"
TARGET_FILE="$2"
TEMP_DIR="/tmp/snapshot_download_$$"

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TEMP_DIR"

log_info "Downloading snapshot from $SNAPSHOT_URL to $TARGET_FILE..."

# Try to download pre-built snapshot using skopeo/crane
if command -v skopeo >/dev/null 2>&1; then
    log_info "Using skopeo to download snapshot"
    if skopeo copy "docker://${SNAPSHOT_URL}" "oci-archive:${TEMP_DIR}/archive.tar" 2>/dev/null; then
        log_info "Successfully downloaded snapshot archive"
        # Extract the actual qcow2 file from the OCI archive
        if tar -xf "${TEMP_DIR}/archive.tar" -C "$TEMP_DIR" --wildcards "*/layer.tar" 2>/dev/null; then
            # Find and extract the qcow2 from the layer
            LAYER_TAR=$(find "$TEMP_DIR" -name "layer.tar" | head -1)
            if [ -n "$LAYER_TAR" ] && tar -tf "$LAYER_TAR" | grep -q "\.qcow2$"; then
                tar -xf "$LAYER_TAR" -C "$TEMP_DIR" --wildcards "*.qcow2"
                EXTRACTED_QCOW2=$(find "$TEMP_DIR" -name "*.qcow2" -not -path "*/tmp/win98_*" | head -1)
                if [ -n "$EXTRACTED_QCOW2" ]; then
                    mv "$EXTRACTED_QCOW2" "$TARGET_FILE"
                    log_success "Successfully downloaded and extracted pre-built snapshot"
                    exit 0
                fi
            fi
        fi
    else
        log_error "Failed to download snapshot with skopeo"
    fi
elif command -v crane >/dev/null 2>&1; then
    log_info "Using crane to download snapshot"
    if crane export "$SNAPSHOT_URL" - | tar -x -C "$TEMP_DIR" --wildcards "*.qcow2" 2>/dev/null; then
        EXTRACTED_QCOW2=$(find "$TEMP_DIR" -name "*.qcow2" -not -path "*/tmp/win98_*" | head -1)
        if [ -n "$EXTRACTED_QCOW2" ]; then
            mv "$EXTRACTED_QCOW2" "$TARGET_FILE"
            log_success "Successfully downloaded and extracted pre-built snapshot"
            exit 0
        fi
    else
        log_error "Failed to download snapshot with crane"
    fi
else
    log_error "No container registry tools (skopeo/crane) available"
fi

exit 1
