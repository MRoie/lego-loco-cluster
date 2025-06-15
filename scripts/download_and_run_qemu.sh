#!/usr/bin/env bash
# download_and_run_qemu.sh -- fetch the Win98 qcow2 image and run the qemu container
set -euo pipefail

GDRIVE_ID="19UD-SRbTY5qyvsSeNhyX7fIaI6cet8Fb"
WORKDIR=${WORKDIR:-$(pwd)/images}
QCOW_NAME="win98.qcow2"
QCOW_PATH="$WORKDIR/$QCOW_NAME"

mkdir -p "$WORKDIR"

for cmd in aria2c curl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    if [ "$cmd" = "aria2c" ]; then
      echo "$cmd is required. Install with: sudo apt-get install -y aria2" >&2
    else
      echo "$cmd is required. Install with: sudo apt-get install -y $cmd" >&2
    fi
    exit 1
  fi
done

download_parallel() {
  local id="$1" out="$2"
  local cookie html
  cookie=$(mktemp)
  html=$(mktemp)
  local base="https://drive.google.com/uc?export=download&id=${id}"
  echo "==> Fetching confirmation token"
  curl -L -c "$cookie" -s "$base" -o "$html"

  local confirm uuid
  confirm=$(grep -o 'name="confirm" value="[^" ]*"' "$html" | head -n1 | sed 's/.*value="//;s/"//')
  uuid=$(grep -o 'name="uuid" value="[^" ]*"' "$html" | head -n1 | sed 's/.*value="//;s/"//')
  if [ -z "$confirm" ]; then
    echo "Failed to retrieve confirmation token" >&2
    rm -f "$cookie" "$html"
    return 1
  fi

  local url="https://drive.usercontent.google.com/download?id=${id}&export=download&confirm=${confirm}"
  if [ -n "$uuid" ]; then
    url="${url}&uuid=${uuid}"
  fi

  echo "==> Downloading qcow2 image in parallel"
  local conns=${CONNS:-16}
  local splits=${SPLITS:-32}
  local dir=$(dirname "$out")
  local filename=$(basename "$out")
  aria2c -c -x "$conns" -s "$splits" -k 1M --load-cookies "$cookie" "$url" -d "$dir" -o "$filename"
  rm -f "$cookie" "$html"
}

echo "==> Downloading qcow2 image from Google Drive"
if [ ! -f "$QCOW_PATH" ]; then
  download_parallel "$GDRIVE_ID" "$QCOW_PATH"
else
  echo "Using existing $QCOW_PATH"
fi

echo "==> Setting up network bridge"
./scripts/setup_bridge.sh

# Check if we should use pre-built image or build locally
USE_PUBLISHED_IMAGE=${USE_PUBLISHED_IMAGE:-false}
IMAGE_REGISTRY="ghcr.io/mroie/qemu-loco:latest"

if [ "$USE_PUBLISHED_IMAGE" = "true" ]; then
  echo "==> Pulling qemu-loco container from registry"
  docker pull "$IMAGE_REGISTRY"
  docker tag "$IMAGE_REGISTRY" qemu-loco
else
  echo "==> Building qemu-loco container locally"
  docker build -t qemu-loco ./containers/qemu
fi

echo "==> Saving Docker image as qemu-loco.tar"
docker save qemu-loco | gzip > "$WORKDIR/qemu-loco.tar.gz"

echo "==> Running qemu-loco container"
docker run --rm --network host --cap-add=NET_ADMIN --device /dev/net/tun \
  -e TAP_IF=tap0 -e BRIDGE=loco-br \
  -v "$WORKDIR/win98.qcow2:/images/win98.qcow2" \
  qemu-loco

