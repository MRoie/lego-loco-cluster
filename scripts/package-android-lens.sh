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
#
#   bash install.sh              # setup + try to download the golden image
#   bash install.sh --no-image   # skip the image download
#   SKIP_IMAGE=1 bash install.sh
set -e
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Android shared storage (/storage/emulated, /sdcard) is FUSE/sdcardfs: it has
# no symlink or exec-bit support, so `npm install` fails there (EACCES symlink).
# Relocate the bundle into Termux $HOME (real ext4) and continue from there.
case "$SELF" in
  /storage/*|/sdcard/*|/mnt/*)
    DEST="$HOME/loco-lens-android"
    echo "Shared storage detected ($SELF)."
    echo ">> Copying bundle to $DEST (npm symlinks need the ext4 home fs)..."
    mkdir -p "$DEST"
    cp -a "$SELF"/. "$DEST"/
    exec bash "$DEST/install.sh" "$@"
    ;;
esac
HERE="$SELF"

WANT_IMAGE=1
for a in "$@"; do [ "$a" = "--no-image" ] && WANT_IMAGE=0; done
[ "${SKIP_IMAGE:-0}" = "1" ] && WANT_IMAGE=0

echo "== Loco Lens — Termux install =="
if command -v pkg >/dev/null 2>&1; then
  echo "[1/4] Installing Termux packages..."
  pkg install -y qemu-system-i386-headless qemu-utils nodejs python netcat-openbsd procps coreutils skopeo
else
  echo "WARNING: 'pkg' not found — not Termux? Skipping package install." >&2
fi

echo "[2/4] Installing lens-server node deps..."
if ! ( cd "$HERE/lens" && npm install --no-audit --no-fund ); then
  echo "   npm install failed; retrying without optional deps (sharp) + --no-bin-links..."
  ( cd "$HERE/lens" && npm install --no-audit --no-fund --omit=optional --no-bin-links ) || \
    echo "   WARNING: node deps incomplete — the lens may run raw-frame-only." >&2
fi

chmod +x "$HERE"/*.sh "$HERE"/qemu/*.sh "$HERE"/qemu/image/*.sh 2>/dev/null || true
mkdir -p "$HOME/loco-runtime/run" "$HOME/loco-runtime/images" "$HOME/loco-runtime/state"

echo "[3/4] Golden image..."
if [ "$WANT_IMAGE" = "1" ]; then
  if ! bash "$HERE/fetch-image.sh"; then
    echo "   Image not fetched (not published yet, or needs GHCR_TOKEN)."
    echo "   Provide it manually at ~/loco-runtime/images/win98.qcow2, or re-run:"
    echo "     bash $HERE/fetch-image.sh"
  fi
else
  echo "   Skipped (--no-image). Put the qcow2 at ~/loco-runtime/images/win98.qcow2."
fi

echo "[4/4] Done."
echo
echo "Run:   $HERE/run-all.sh"
echo "Watch: ws://<phone-ip>:3001/ws/lens/local"
EOF
chmod +x "$BUNDLE/install.sh"

# --- Golden image fetch (skopeo → extract qcow2 from the OCI carrier) --------
cat > "$BUNDLE/fetch-image.sh" <<'EOF'
#!/usr/bin/env bash
# Pull the Win98+Loco golden image from GHCR and place the qcow2 at
# ~/loco-runtime/images/win98.qcow2. Public images pull anonymously; for a
# private image set GHCR_TOKEN (+ optional GHCR_USER, default MRoie).
#
#   bash fetch-image.sh [IMAGE_REF] [DEST_QCOW2]
set -e
IMAGE="${1:-ghcr.io/mroie/lego-loco-cluster/win98-loco-golden:safe512-v1}"
DEST="${2:-$HOME/loco-runtime/images/win98.qcow2}"
mkdir -p "$(dirname "$DEST")"

if [ -f "$DEST" ]; then echo "Image already present: $DEST"; exit 0; fi
if ! command -v skopeo >/dev/null 2>&1; then
  pkg install -y skopeo >/dev/null 2>&1 || { echo "skopeo not available (pkg install skopeo)"; exit 1; }
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CREDS=()
[ -n "${GHCR_TOKEN:-}" ] && CREDS=(--src-creds "${GHCR_USER:-MRoie}:${GHCR_TOKEN}")

echo "Pulling $IMAGE (this is ~500 MB)..."
skopeo copy "${CREDS[@]}" --override-os linux "docker://$IMAGE" "oci-archive:$TMP/img.tar"

echo "Extracting qcow2..."
tar -xf "$TMP/img.tar" -C "$TMP"
# Single-layer scratch carrier: the qcow2 layer is by far the largest blob.
LAYER="$(ls -S "$TMP"/blobs/sha256/* 2>/dev/null | head -1)"
[ -n "$LAYER" ] || { echo "no image layers found"; exit 1; }
QC="$(tar -tf "$LAYER" 2>/dev/null | grep -E '\.qcow2(\.builtin)?$' | head -1 || true)"
[ -n "$QC" ] || { echo "no qcow2 in the image layer"; exit 1; }
tar -xf "$LAYER" -C "$TMP" "$QC"
mv "$TMP/$QC" "$DEST"
echo "Placed golden image at $DEST"
EOF
chmod +x "$BUNDLE/fetch-image.sh"

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
unzip loco-lens-android.zip        # or: tar -xzf loco-lens-android.tar.gz
cd loco-lens-android
bash install.sh
```
Installs QEMU + Node in Termux, the lens-server deps, and downloads the golden
image from GHCR. `bash install.sh --no-image` to skip the download.

> **Important — don't run from `/sdcard` / `Download`.** Android shared storage
> can't create symlinks, so `npm install` fails there (`EACCES symlink`). You do
> NOT need `sudo`. install.sh auto-detects this and copies the bundle to
> `~/loco-lens-android` (Termux's ext4 home) before installing — just re-run it
> from there if prompted, or unzip into `$HOME` to begin with:
> `cd ~ && unzip /sdcard/Download/loco-lens-android.zip && cd loco-lens-android && bash install.sh`

## The image
`install.sh` pulls the ~500 MB golden qcow2 from GHCR via `skopeo` to
`~/loco-runtime/images/win98.qcow2`. If it isn't published yet (or is private),
set `GHCR_TOKEN` and re-run `bash fetch-image.sh`, or copy the qcow2 there
manually (adb push / a file manager into `~/loco-runtime/images/`).

## Run
```bash
./run-all.sh                 # boots the emulator + starts the lens server
# view the full game: a VNC viewer / Termux:X11 on 127.0.0.1:5901
# watch: point it at ws://<phone-ip>:3001/ws/lens/local
```

Just the lens (emulator already running): `./run-lens.sh`
Multiple local instances: `LENS_INSTANCES='local=127.0.0.1:5901,second=127.0.0.1:5902' ./run-lens.sh`

## Notes
- `sharp` is optional; if it fails to build, install falls back to raw frames
  and the lens still works.
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
