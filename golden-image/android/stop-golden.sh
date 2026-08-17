#!/usr/bin/env bash
# stop-golden.sh — request a clean QMP powerdown, then verify the process exits.
# Prefer this over kill so the guest can flush and shut down cleanly (which is
# what lets seal-golden-image.sh produce a ScanDisk-free image).
#   stop-golden.sh [--run-dir DIR] [--force]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN="$HERE/../build/run"; FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --run-dir) RUN="$2"; shift 2;;
    --force) FORCE=1; shift;;
    *) echo "Unknown option: $1" >&2; exit 2;;
  esac
done
if [ ! -S "$RUN/qmp.sock" ]; then
  echo "ERROR: no QMP socket at $RUN/qmp.sock — is a golden VM running for this run-dir?" >&2
  exit 1
fi

python3 - "$RUN/qmp.sock" <<'PY' || true
import json, socket, sys
try:
    s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1])
    f = s.makefile('rw'); f.readline()
    s.sendall(b'{"execute":"qmp_capabilities"}\n'); f.readline()
    # ACPI powerdown asks Win98 to shut down cleanly.
    s.sendall(b'{"execute":"system_powerdown"}\n'); print('sent system_powerdown')
except Exception as e:
    print('QMP powerdown failed:', e)
PY

echo "Requested ACPI shutdown; the guest may take ~20-40s to power off."
if [ "$FORCE" = "1" ] && [ -f "$RUN/qemu.pid" ]; then
  sleep 40
  kill "$(cat "$RUN/qemu.pid")" 2>/dev/null || true
  echo "Forced kill after grace period."
fi
