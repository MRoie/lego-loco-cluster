#!/usr/bin/env bash
# ============================================================================
# package-android-lens.sh — build a self-contained Termux bundle (zip) that
# runs QEMU + the Loco Lens on Android with a one-command install.
# ============================================================================
# The bundle is SOURCE-ONLY (small): install.sh runs `npm install` and the
# Termux `pkg install` steps ON the device, so native deps (sharp arm64) and
# QEMU are fetched for the phone's architecture. The 526 MB golden qcow2 is NOT
# included — pull it from GHCR or copy it separately.
#
#   scripts/package-android-lens.sh [--out DIR]
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="build"
[ "${1:-}" = "--out" ] && OUT="$2"
mkdir -p "$OUT"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$STAGE/loco-lens-android"
mkdir -p "$BUNDLE/qemu" "$BUNDLE/lens/backend/services" "$BUNDLE/lens/backend/routes" \
         "$BUNDLE/lens/backend/protocol" "$BUNDLE/lens/backend/utils"

echo "[pkg] staging QEMU + image scripts"
cp golden-image/android/qemu-launcher.sh golden-image/android/bootstrap-android.sh \
   golden-image/android/run-golden.sh golden-image/android/stop-golden.sh "$BUNDLE/qemu/"
cp -r golden-image/image "$BUNDLE/qemu/image"
cp golden-image/tests/qmp.py golden-image/tests/rfb_probe.py "$BUNDLE/qemu/" 2>/dev/null || true

echo "[pkg] staging lens server + backend modules"
cp golden-image/android/lens-server.js "$BUNDLE/lens/lens-server.js"
cp backend/routes/watch.js                    "$BUNDLE/lens/backend/routes/"
cp backend/protocol/watchProtocol.js          "$BUNDLE/lens/backend/protocol/"
for m in instanceResolver rfbFramebuffer lensBridge lensCrop lensEncoder watchPairing; do
  cp "backend/services/$m.js" "$BUNDLE/lens/backend/services/"
done

# Lightweight logger shim — no winston / file rotation on the phone.
cat > "$BUNDLE/lens/backend/utils/logger.js" <<'EOF'
// Minimal console logger (Android bundle) — same API as the backend logger.
function fmt(level, msg, meta) {
  const m = meta && Object.keys(meta).length ? ' ' + JSON.stringify(meta) : '';
  return `[${new Date().toISOString()}] [${level}] ${msg}${m}`;
}
const logger = {
  info:  (m, meta) => console.log(fmt('INFO', m, meta)),
  warn:  (m, meta) => console.warn(fmt('WARN', m, meta)),
  error: (m, meta) => console.error(fmt('ERROR', m, meta)),
  debug: (m, meta) => { if (process.env.LENS_DEBUG) console.log(fmt('DEBUG', m, meta)); },
};
logger.createLogger = () => logger;
module.exports = logger;
module.exports.createLogger = () => logger;
EOF

# package.json for the lens server (minimal; sharp optional).
cat > "$BUNDLE/lens/package.json" <<'EOF'
{
  "name": "loco-lens-android",
  "version": "0.1.0",
  "private": true,
  "main": "lens-server.js",
  "dependencies": {
    "express": "^4.18.2",
    "ws": "^8.18.2",
    "rfb2": "^0.2.2"
  },
  "optionalDependencies": {
    "sharp": "^0.33.5"
  }
}
EOF

# --- One-command Termux install --------------------------------------------
cat > "$BUNDLE/install.sh" <<'EOF'
#!/usr/bin/env bash
# One-command Termux setup for the Loco Lens.
set -e
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "== Loco Lens — Termux install =="
if command -v pkg >/dev/null 2>&1; then
  echo "[1/3] Installing Termux packages..."
  pkg install -y qemu-system-i386-headless qemu-utils nodejs python netcat-openbsd procps coreutils
else
  echo "WARNING: 'pkg' not found — not Termux? Skipping package install." >&2
fi
echo "[2/3] Installing lens-server node deps (fetches sharp for this arch)..."
( cd "$HERE/lens" && npm install --no-audit --no-fund )
chmod +x "$HERE"/*.sh "$HERE"/qemu/*.sh "$HERE"/qemu/image/*.sh 2>/dev/null || true
mkdir -p "$HOME/loco-runtime/run" "$HOME/loco-runtime/images" "$HOME/loco-runtime/state"
echo "[3/3] Done."
echo
echo "Next:"
echo "  1. Put your golden qcow2 at ~/loco-runtime/images/win98.qcow2"
echo "     (pull from GHCR, or copy win98-loco-golden-safe512.qcow2 there)."
echo "  2. Start the emulator:   $HERE/run-all.sh"
echo "  3. Point the M5Stack watch at ws://<phone-ip>:3001/ws/lens/local"
EOF
chmod +x "$BUNDLE/install.sh"

# --- Convenience runners ----------------------------------------------------
cat > "$BUNDLE/run-lens.sh" <<'EOF'
#!/usr/bin/env bash
# Start the standalone lens server (taps VNC 127.0.0.1:5901 by default).
set -e
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LENS_BACKEND_DIR="$HERE/lens/backend"
export LENS_INSTANCES="${LENS_INSTANCES:-local=127.0.0.1:5901}"
export LENS_PORT="${LENS_PORT:-3001}"
exec node "$HERE/lens/lens-server.js"
EOF
chmod +x "$BUNDLE/run-lens.sh"

cat > "$BUNDLE/run-all.sh" <<'EOF'
#!/usr/bin/env bash
# Boot the golden image (safe512, VNC :5901) and start the lens server.
set -e
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMG="${1:-$HOME/loco-runtime/images/win98.qcow2}"
[ -f "$IMG" ] || { echo "ERROR: image not found: $IMG (see install.sh step 1)"; exit 1; }
echo "Booting emulator (VNC 127.0.0.1:5901)..."
bash "$HERE/qemu/qemu-launcher.sh" --disk "$IMG" --profile safe512 \
  --run-dir "$HOME/loco-runtime/run" --vnc-display 1
echo "Starting lens server..."
exec "$HERE/run-lens.sh"
EOF
chmod +x "$BUNDLE/run-all.sh"

cat > "$BUNDLE/README.md" <<'EOF'
# Loco Lens — Android (Termux) bundle

Run Windows 98 + Lego Loco under QEMU on your phone and drive an M5Stack
StopWatch "Loco Lens" from it — no cluster, no React app. The VNC is the
full-screen front; the lens server taps the same VNC for the watch crop.

## Install (one command)
```bash
unzip loco-lens-android.zip && cd loco-lens-android
bash install.sh
```
This installs QEMU + Node in Termux and the lens-server deps (incl. the arm64
`sharp` build).

## Provide the image
The Win98+Loco golden qcow2 is NOT in this zip (it's ~500 MB). Put it at:
```
~/loco-runtime/images/win98.qcow2
```
Pull it from GHCR (once published) or copy it over (adb push / a file manager).

## Run
```bash
./run-all.sh                 # boots the emulator + starts the lens server
# view the full game: a VNC viewer / Termux:X11 on 127.0.0.1:5901
# watch: point it at ws://<phone-ip>:3001/ws/lens/local
```

Just the lens (emulator already running): `./run-lens.sh`
Multiple local instances: `LENS_INSTANCES='local=127.0.0.1:5901,second=127.0.0.1:5902' ./run-lens.sh`

## Notes
- `sharp` is optional; if it fails to build, the lens falls back to raw frames
  and still works.
- Keep VNC bound to localhost unless behind a secure transport.
- Firmware + flasher for the watch live in the repo under `m5stack-lens/`.
EOF

echo "[pkg] pruning build junk"
find "$BUNDLE" -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true
find "$BUNDLE" -name '*.pyc' -delete 2>/dev/null || true

echo "[pkg] archiving (zip + tar.gz)"
mkdir -p "$OUT"
( cd "$STAGE" && zip -qr "loco-lens-android.zip" "loco-lens-android" )
( cd "$STAGE" && tar -czf "loco-lens-android.tar.gz" "loco-lens-android" )
mv "$STAGE/loco-lens-android.zip" "$OUT/loco-lens-android.zip"
mv "$STAGE/loco-lens-android.tar.gz" "$OUT/loco-lens-android.tar.gz"
( cd "$OUT" && sha256sum loco-lens-android.zip loco-lens-android.tar.gz > loco-lens-android.sha256 2>/dev/null || \
  shasum -a 256 loco-lens-android.zip loco-lens-android.tar.gz > loco-lens-android.sha256 )
echo "[pkg] wrote:"
ls -la "$OUT"/loco-lens-android.* | awk '{print "  ", $5, $NF}'
