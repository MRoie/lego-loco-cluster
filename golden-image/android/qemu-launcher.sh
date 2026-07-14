#!/usr/bin/env bash
# ============================================================================
# qemu-launcher.sh — reusable QEMU launcher for the Win98 + Lego Loco image
# ============================================================================
# Portable across Android (Termux), Linux, macOS and containers. Encodes the
# working baseline and the bug fixes discovered during Android bring-up:
#   * explicit blockdev + single ide-hd (no duplicate IDE attach)
#   * PS/2 input on first boot; USB tablet only when ENABLE_USB=1
#   * password-protected localhost VNC via a QEMU secret file
#   * QMP + monitor unix sockets, serial captured to a log (boot sentinel)
#
# This launcher does NOT modify disks. It refuses to start if a QEMU is
# already running against the same run directory.
#
# Usage:
#   qemu-launcher.sh --disk PATH [options]
#
# Options:
#   --disk PATH          qcow2 to boot (required)
#   --profile NAME       safe512 (default) | highmem1024
#   --run-dir DIR        pid/sockets/logs dir (default: ~/loco-runtime/run)
#   --vnc-secret FILE    VNC password secret file (default: <run>/../secrets/vnc-password)
#   --vnc-display N      VNC display number (default: 1 -> 127.0.0.1:5901)
#   --display MODE       none (default, VNC only) | sdl | gtk
#   --enable-usb         attach USB controller + tablet (needs guest USB drivers)
#   --tcg-cache MB       TCG translation cache size (default per profile)
#   --extra-args "..."   extra raw QEMU args (advanced)
#   --dry-run            print the assembled command and exit
# ============================================================================
set -euo pipefail

DISK=""
PROFILE="safe512"
RUN_DIR="${LOCO_RUN_DIR:-$HOME/loco-runtime/run}"
VNC_SECRET=""
VNC_DISPLAY=1
DISPLAY_MODE="none"
ENABLE_USB="${ENABLE_USB:-0}"
TCG_CACHE=""
EXTRA_ARGS=""
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --disk) DISK="$2"; shift 2;;
    --profile) PROFILE="$2"; shift 2;;
    --run-dir) RUN_DIR="$2"; shift 2;;
    --vnc-secret) VNC_SECRET="$2"; shift 2;;
    --vnc-display) VNC_DISPLAY="$2"; shift 2;;
    --display) DISPLAY_MODE="$2"; shift 2;;
    --enable-usb) ENABLE_USB=1; shift;;
    --tcg-cache) TCG_CACHE="$2"; shift 2;;
    --extra-args) EXTRA_ARGS="$2"; shift 2;;
    --dry-run) DRY_RUN=1; shift;;
    *) echo "Unknown option: $1" >&2; exit 2;;
  esac
done

[ -n "$DISK" ] || { echo "ERROR: --disk is required" >&2; exit 2; }
[ -f "$DISK" ] || { echo "ERROR: disk not found: $DISK" >&2; exit 2; }

# Profile → RAM + default TCG cache. Windows 98 stays single-vCPU always.
case "$PROFILE" in
  safe512)     RAM=512;  DEF_TCG=1024;;
  highmem1024) RAM=1024; DEF_TCG=1024;;
  *) echo "ERROR: unknown profile '$PROFILE' (safe512|highmem1024)" >&2; exit 2;;
esac
TCG_CACHE="${TCG_CACHE:-$DEF_TCG}"

mkdir -p "$RUN_DIR"
PID_FILE="$RUN_DIR/qemu.pid"
QMP_SOCK="$RUN_DIR/qmp.sock"
MON_SOCK="$RUN_DIR/qemu-monitor.sock"
SERIAL_LOG="$RUN_DIR/serial.log"
QEMU_LOG="$RUN_DIR/qemu.log"

# Refuse to start over a live QEMU using the same run dir.
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
  echo "ERROR: QEMU already running (pid $(cat "$PID_FILE")) for run dir $RUN_DIR" >&2
  exit 1
fi

# QEMU binary — prefer the headless build on Termux (avoids GUI deps); fall
# back to the full binary elsewhere.
QEMU_BIN="$(command -v qemu-system-i386-headless || command -v qemu-system-i386 || true)"
if [ -z "$QEMU_BIN" ]; then
  if [ "$DRY_RUN" = "1" ]; then
    QEMU_BIN="qemu-system-i386"   # placeholder so --dry-run can print the command
  else
    echo "ERROR: qemu-system-i386[-headless] not found on PATH" >&2; exit 3
  fi
fi

# Assemble arguments as an array (safe quoting).
ARGS=(
  -M pc -cpu pentium3 -m "$RAM" -smp 1
  -accel tcg,tb-size="$TCG_CACHE"
  # Explicit disk backend: exactly one IDE device, no auto -drive index clash.
  -blockdev "driver=file,filename=${DISK},node-name=loco_file,auto-read-only=off"
  -blockdev "driver=qcow2,file=loco_file,node-name=loco_disk"
  -device "ide-hd,drive=loco_disk,bus=ide.0,unit=0"
  -vga std
  -netdev "user,id=lan0" -device "ne2k_pci,netdev=lan0"
  -device sb16,audiodev=snd0 -audiodev "none,id=snd0"
  -rtc base=localtime
  -qmp "unix:${QMP_SOCK},server,nowait"
  -monitor "unix:${MON_SOCK},server,nowait"
  -serial "file:${SERIAL_LOG}"
  -pidfile "$PID_FILE"
)

# VNC with a password secret when provided, else open localhost VNC.
if [ -z "$VNC_SECRET" ]; then
  VNC_SECRET="$(dirname "$RUN_DIR")/secrets/vnc-password"
fi
if [ -f "$VNC_SECRET" ]; then
  ARGS+=( -object "secret,id=vncpass,file=${VNC_SECRET},format=raw" )
  ARGS+=( -vnc "127.0.0.1:${VNC_DISPLAY},password-secret=vncpass,share=force-shared" )
else
  echo "WARNING: no VNC secret at $VNC_SECRET — binding OPEN localhost VNC" >&2
  ARGS+=( -vnc "127.0.0.1:${VNC_DISPLAY},share=force-shared" )
fi

# Optional local display (Termux:X11 / desktop). VNC stays active alongside.
case "$DISPLAY_MODE" in
  none) ARGS+=( -display none );;
  sdl)  ARGS+=( -display "sdl,gl=off" );;
  gtk)  ARGS+=( -display "gtk,gl=off" );;
  *) echo "ERROR: unknown --display '$DISPLAY_MODE'" >&2; exit 2;;
esac

# USB tablet only after guest USB drivers exist (first-boot uses PS/2).
if [ "$ENABLE_USB" = "1" ]; then
  ARGS+=( -device qemu-xhci -device usb-tablet )
fi

# shellcheck disable=SC2206
[ -n "$EXTRA_ARGS" ] && ARGS+=( $EXTRA_ARGS )

if [ "$DRY_RUN" = "1" ]; then
  printf '%q ' "$QEMU_BIN" "${ARGS[@]}"; echo
  exit 0
fi

echo "Starting QEMU: profile=$PROFILE ram=${RAM}MB tcg=${TCG_CACHE}MB vnc=127.0.0.1:$((5900+VNC_DISPLAY))"
"$QEMU_BIN" "${ARGS[@]}" >"$QEMU_LOG" 2>&1 &
echo "QEMU pid=$! (pidfile $PID_FILE)"
echo "  QMP:    $QMP_SOCK"
echo "  serial: $SERIAL_LOG  (boot sentinel: LOCO_READY)"
echo "  VNC:    127.0.0.1:$((5900+VNC_DISPLAY))"
