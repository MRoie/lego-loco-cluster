#!/usr/bin/env bash
# import-current-android.sh — flatten a (possibly backing-chained) qcow2 into a
# standalone base image. Never mutates the source.
#   import-current-android.sh SRC DEST
set -euo pipefail
SRC="${1:?usage: import-current-android.sh SRC DEST}"
DEST="${2:?usage: import-current-android.sh SRC DEST}"
[ -f "$SRC" ] || { echo "ERROR: source not found: $SRC" >&2; exit 1; }
mkdir -p "$(dirname "$DEST")"

echo "[import] qemu-img check on source..."
qemu-img check "$SRC" || echo "[import] WARNING: source reported check issues (continuing)"

echo "[import] converting to standalone base: $DEST"
# convert collapses the backing chain into one file (no -b => standalone).
qemu-img convert -p -O qcow2 -o cluster_size=2M "$SRC" "$DEST.tmp"
mv "$DEST.tmp" "$DEST"
qemu-img info "$DEST" | grep -iE 'file format|virtual size|disk size|backing'
echo "[import] done: $DEST"
