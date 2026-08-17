#!/usr/bin/env bash
# e2e.sh — host-side acceptance checks against a running golden VM.
# Does NOT require proprietary guest media; it checks the HOST contract:
#   * QEMU process alive
#   * QMP reports running
#   * VNC accepts an RFB handshake
#   * serial log contains LOCO_READY (guest boot sentinel)
#
#   e2e.sh [--run-dir DIR] [--vnc-port 5901]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN="$HERE/../build/run"; VNC_PORT=5901
while [ $# -gt 0 ]; do
  case "$1" in
    --run-dir) RUN="$2"; shift 2;;
    --vnc-port) VNC_PORT="$2"; shift 2;;
    *) echo "Unknown option: $1" >&2; exit 2;;
  esac
done

fail=0
pass() { echo "  PASS: $1"; }
bad()  { echo "  FAIL: $1"; fail=1; }

echo "== golden-image host acceptance =="

# 1. QEMU alive
if [ -f "$RUN/qemu.pid" ] && kill -0 "$(cat "$RUN/qemu.pid")" 2>/dev/null; then
  pass "QEMU process alive (pid $(cat "$RUN/qemu.pid"))"
else
  bad "QEMU process not running"
fi

# 2. QMP running
if [ -S "$RUN/qmp.sock" ]; then
  st="$(python3 "$HERE/qmp.py" "$RUN/qmp.sock" status 2>/dev/null || true)"
  echo "$st" | grep -q '"running": true' && pass "QMP reports running" || bad "QMP not running ($st)"
else
  bad "no QMP socket at $RUN/qmp.sock"
fi

# 3. VNC handshake
if python3 "$HERE/rfb_probe.py" 127.0.0.1 "$VNC_PORT" >/dev/null 2>&1; then
  pass "VNC accepts RFB handshake on $VNC_PORT"
else
  bad "VNC handshake failed on $VNC_PORT"
fi

# 4. Boot sentinel
if [ -f "$RUN/serial.log" ] && grep -q LOCO_READY "$RUN/serial.log"; then
  pass "serial log contains LOCO_READY"
else
  bad "LOCO_READY not seen in $RUN/serial.log (guest sentinel / still booting)"
fi

echo "== $( [ $fail -eq 0 ] && echo ALL PASS || echo FAILURES ) =="
exit $fail
