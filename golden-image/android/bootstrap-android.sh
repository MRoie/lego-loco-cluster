#!/usr/bin/env bash
# ============================================================================
# bootstrap-android.sh — one command to stand up the Win98 provisioning VM
#                        on Android (Termux) from the current image.
# ============================================================================
# Verifies Termux, installs deps, imports+flattens the current disk into a
# standalone base, creates a provisioning overlay, and launches the safe512
# profile with localhost password-VNC — then prints the connection details.
#
#   bootstrap-android.sh [--no-start] [--force-reimport] [--source PATH] [--x11]
# ============================================================================
set -euo pipefail

NO_START=0
FORCE_REIMPORT=0
SOURCE=""
USE_X11=0
while [ $# -gt 0 ]; do
  case "$1" in
    --no-start) NO_START=1; shift;;
    --force-reimport) FORCE_REIMPORT=1; shift;;
    --source) SOURCE="$2"; shift 2;;
    --x11) USE_X11=1; shift;;
    *) echo "Unknown option: $1" >&2; exit 2;;
  esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME="$HOME/loco-runtime"
BUILD="$HERE/../build"
PRIVATE="$HERE/../assets/private"

log() { echo "[bootstrap] $*"; }

# 1. Termux check
if [ -z "${PREFIX:-}" ] || [ "${PREFIX#*com.termux}" = "$PREFIX" ]; then
  echo "WARNING: this does not look like Termux (\$PREFIX=$PREFIX)." >&2
  echo "         Continuing anyway — package install is skipped off-Termux." >&2
  ON_TERMUX=0
else
  ON_TERMUX=1
fi

# 2. Dependencies
if [ "$ON_TERMUX" = "1" ]; then
  log "Installing packages via pkg..."
  pkg install -y qemu-system-i386-headless qemu-utils python netcat-openbsd procps coreutils >/dev/null
  if [ "$USE_X11" = "1" ]; then
    pkg install -y x11-repo >/dev/null || true
    pkg install -y termux-x11-nightly qemu-system-i386 >/dev/null || true
  fi
fi

# 3. Refuse to touch disks while a QEMU is running
if [ -f "$RUNTIME/run/qemu.pid" ] && kill -0 "$(cat "$RUNTIME/run/qemu.pid" 2>/dev/null)" 2>/dev/null; then
  echo "ERROR: a QEMU is running (pid $(cat "$RUNTIME/run/qemu.pid")). Stop it first." >&2
  exit 1
fi

mkdir -p "$BUILD/work" "$BUILD/secrets" "$BUILD/run" "$PRIVATE"

# 4-6. Select source and flatten into a standalone base
BASE="$PRIVATE/win98-base.qcow2"
if [ -n "$SOURCE" ]; then
  SRC="$SOURCE"
elif [ -f "$RUNTIME/state/loco-android.qcow2" ]; then
  SRC="$RUNTIME/state/loco-android.qcow2"          # writable Android overlay
elif [ -f "$RUNTIME/images/win98.qcow2" ]; then
  SRC="$RUNTIME/images/win98.qcow2"                # fallback base
else
  echo "ERROR: no source image found. Pass --source PATH." >&2
  exit 1
fi

if [ ! -f "$BASE" ] || [ "$FORCE_REIMPORT" = "1" ]; then
  log "Flattening $SRC -> $BASE (standalone, no backing chain)..."
  bash "$HERE/../image/import-current-android.sh" "$SRC" "$BASE"
else
  log "Base already present: $BASE (use --force-reimport to rebuild)"
fi

# 7. VNC secret
SECRET="$BUILD/secrets/vnc-password"
if [ ! -f "$SECRET" ]; then
  log "Generating VNC password secret..."
  head -c 12 /dev/urandom | base64 | tr -d '/+=' | head -c 12 > "$SECRET"
  chmod 600 "$SECRET"
fi

# 8. Provisioning overlay
WORK="$BUILD/work/win98-loco-provisioning.qcow2"
bash "$HERE/../image/create-work-image.sh" "$BASE" "$WORK"

# 9-10. Launch
if [ "$NO_START" = "1" ]; then
  log "Provisioning overlay ready: $WORK (not started, --no-start)"
  exit 0
fi

DISPLAY_MODE="none"
[ "$USE_X11" = "1" ] && DISPLAY_MODE="sdl"
bash "$HERE/qemu-launcher.sh" \
  --disk "$WORK" \
  --profile safe512 \
  --run-dir "$BUILD/run" \
  --vnc-secret "$SECRET" \
  --display "$DISPLAY_MODE"

echo
log "Provisioning VM started."
log "  VNC:      127.0.0.1:5901  (password in $SECRET)"
log "  Serial:   $BUILD/run/serial.log  (waits for LOCO_READY)"
log "Next: connect a VNC viewer and follow golden-image/docs/DRIVER-INSTALL-CHECKLIST.md"
