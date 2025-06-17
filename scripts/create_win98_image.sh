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

# Ensure qemu-img is available (works with qemu-img or qemu-img.exe)
if command -v qemu-img >/dev/null; then
  QEMU_IMG="$(command -v qemu-img)"
elif command -v qemu-img.exe >/dev/null; then
  QEMU_IMG="$(command -v qemu-img.exe)"
else
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
"$QEMU_IMG" convert -p -f "$INPUT_FMT" -O raw "$SRC_DISK" "$RAW_OUT"

# Verify MBR signature so the disk is bootable
CHECK_CMD=""
if command -v hexdump >/dev/null; then
  CHECK_CMD="hexdump -v -e '/1 \"%02x\"'"
elif command -v od >/dev/null; then
  CHECK_CMD="od -An -tx1"
fi

if [[ -n "$CHECK_CMD" ]]; then
  if ! dd if="$RAW_OUT" bs=1 skip=510 count=2 2>/dev/null | eval $CHECK_CMD | tr -d ' \n' | grep -qi "55aa"; then
    echo "WARNING: MBR signature not found; image may not be bootable." >&2
  fi
else
  echo "WARNING: hexdump/od not found; skipping boot signature check." >&2
fi

echo "==> Converting $SRC_DISK to QCOW2 image $QCOW_OUT"
"$QEMU_IMG" convert -p -f "$INPUT_FMT" -O qcow2 -o compat=0.10 "$SRC_DISK" "$QCOW_OUT"

echo "Images saved in $OUT_DIR"
