#!/usr/bin/env bash
# seal-golden-image.sh — seal a provisioning overlay into a standalone,
# compressed golden base with checksum + manifest.
#
# ONLY run after the guest has been CLEANLY shut down (Start > Shut Down) so the
# sealed image has no dirty filesystem flag — otherwise every boot runs ScanDisk.
#
#   seal-golden-image.sh WORK OUTPUT_QCOW2 [profile]
set -euo pipefail
WORK="${1:?usage: seal-golden-image.sh WORK OUTPUT [profile]}"
OUT="${2:?usage: seal-golden-image.sh WORK OUTPUT [profile]}"
PROFILE="${3:-safe512}"
[ -f "$WORK" ] || { echo "ERROR: work image not found: $WORK" >&2; exit 1; }
mkdir -p "$(dirname "$OUT")"

echo "[seal] pre-seal integrity check..."
# qemu-img check exit codes: 0=clean, 2=corruption (fatal), 3=leaked clusters
# (harmless wasted space — repair and continue). Anything else we surface.
set +e
qemu-img check -r leaks "$WORK"; CHK=$?
set -e
if [ "$CHK" = "2" ]; then
  echo "[seal] ERROR: image reports corruption (exit 2); refusing to seal." >&2
  exit 1
fi

echo "[seal] converting to standalone compressed golden base..."
# Convert to a temp file and rename atomically so an interrupted seal never
# leaves a partial/corrupt golden image at the final path.
qemu-img convert -p -c -O qcow2 -o cluster_size=2M,lazy_refcounts=on "$WORK" "$OUT.partial"
mv "$OUT.partial" "$OUT"

echo "[seal] checksum + manifest..."
SHA="$(sha256sum "$OUT" | awk '{print $1}')"
echo "$SHA  $(basename "$OUT")" > "$OUT.sha256"

VSIZE="$(qemu-img info --output=json "$OUT" | grep -o '"virtual-size": *[0-9]*' | head -1 | grep -o '[0-9]*')"
DSIZE="$(stat -c %s "$OUT" 2>/dev/null || wc -c < "$OUT")"
cat > "$OUT.manifest.json" <<EOF
{
  "artifact": "$(basename "$OUT")",
  "profile": "$PROFILE",
  "sha256": "$SHA",
  "virtualSizeBytes": ${VSIZE:-0},
  "diskSizeBytes": ${DSIZE:-0},
  "format": "qcow2",
  "standalone": true,
  "sealedNote": "Seal only after a clean Win98 shutdown (no ScanDisk on next boot)."
}
EOF

echo "[seal] done:"
echo "  $OUT"
echo "  $OUT.sha256"
echo "  $OUT.manifest.json"
