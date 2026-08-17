#!/usr/bin/env bash
# create-work-image.sh — create a writable provisioning overlay backed by BASE.
# The overlay keeps the base immutable while you install drivers/Loco.
#   create-work-image.sh BASE WORK
set -euo pipefail
BASE="${1:?usage: create-work-image.sh BASE WORK}"
WORK="${2:?usage: create-work-image.sh BASE WORK}"
[ -f "$BASE" ] || { echo "ERROR: base not found: $BASE" >&2; exit 1; }
mkdir -p "$(dirname "$WORK")"

if [ -f "$WORK" ]; then
  echo "[work] overlay already exists: $WORK (reusing; delete to start fresh)"
  exit 0
fi

echo "[work] creating overlay $WORK backed by $BASE"
qemu-img create -f qcow2 -F qcow2 -b "$BASE" "$WORK" >/dev/null
qemu-img info "$WORK" | grep -iE 'backing file|virtual size'
echo "[work] done"
