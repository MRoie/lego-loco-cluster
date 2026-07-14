#!/usr/bin/env bash
# run-golden.sh — boot a sealed golden image (read-only base + fresh overlay).
#   run-golden.sh [--profile safe512|highmem1024] [--image PATH] [--x11] [--enable-usb]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="safe512"; IMAGE=""; X11=0; USB=0
while [ $# -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2;;
    --image) IMAGE="$2"; shift 2;;
    --x11) X11=1; shift;;
    --enable-usb) USB=1; shift;;
    *) echo "Unknown option: $1" >&2; exit 2;;
  esac
done
IMAGE="${IMAGE:-$HERE/../build/output/win98-loco-$PROFILE.qcow2}"
[ -f "$IMAGE" ] || { echo "ERROR: golden image not found: $IMAGE" >&2; exit 1; }

RUN="$HERE/../build/run"; SECRET="$HERE/../build/secrets/vnc-password"
OVERLAY="$HERE/../build/work/run-$PROFILE.qcow2"
mkdir -p "$(dirname "$OVERLAY")"
[ -f "$OVERLAY" ] || qemu-img create -f qcow2 -F qcow2 -b "$IMAGE" "$OVERLAY" >/dev/null

DISP="none"; [ "$X11" = "1" ] && DISP="sdl"
ARGS=( --disk "$OVERLAY" --profile "$PROFILE" --run-dir "$RUN" --vnc-secret "$SECRET" --display "$DISP" )
[ "$USB" = "1" ] && ARGS+=( --enable-usb )
bash "$HERE/qemu-launcher.sh" "${ARGS[@]}"
