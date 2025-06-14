#!/usr/bin/env bash
# create_win98_image.sh -- Convert a PCem or VHD disk into raw and QCOW2 images

# Exit immediately on errors and print a helpful message
set -euo pipefail
trap 'echo "ERROR: command failed on line $LINENO" >&2' ERR

# Optional environment variable to capture verbose logs
LOG_FILE=${LOG_FILE:-create_win98_image.log}
exec > >(tee -i "$LOG_FILE") 2>&1

SRC_DISK=${1:-}
OUT_DIR=${2:-$(pwd)}

if [[ -z "$SRC_DISK" ]]; then
  echo "Usage: $0 <disk.img|volume.vhd> [output_dir]" >&2
  exit 1
fi

# Ensure qemu-img is available
if ! command -v qemu-img >/dev/null; then
  echo "qemu-img is required but not installed" >&2
  exit 1
fi

if [[ ! -f "$SRC_DISK" ]]; then
  echo "Source disk $SRC_DISK not found" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
RAW_OUT="$OUT_DIR/win98.img"
QCOW_OUT="$OUT_DIR/win98.qcow2"

# Determine input format for qemu-img
INPUT_FMT="raw"
case "${SRC_DISK##*.}" in
  vhd|VHD)
    INPUT_FMT="vpc"
    ;;
esac

echo "==> Converting $SRC_DISK to raw image $RAW_OUT"
qemu-img convert -f "$INPUT_FMT" -O raw "$SRC_DISK" "$RAW_OUT"

echo "==> Converting $SRC_DISK to QCOW2 image $QCOW_OUT"
qemu-img convert -f "$INPUT_FMT" -O qcow2 "$SRC_DISK" "$QCOW_OUT"

echo "Images saved in $OUT_DIR"
