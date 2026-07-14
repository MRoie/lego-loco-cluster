#!/usr/bin/env bash
# prepare-oci-context.sh — stage a sealed qcow2 as an OCI build context so the
# same data payload can be published multi-arch (linux/amd64 + linux/arm64).
# The OCI image is only a carrier; the embedded qcow2 is architecture-neutral.
#
#   prepare-oci-context.sh SEALED_QCOW2 CONTEXT_DIR
set -euo pipefail
SEALED="${1:?usage: prepare-oci-context.sh SEALED_QCOW2 CONTEXT_DIR}"
CTX="${2:?usage: prepare-oci-context.sh SEALED_QCOW2 CONTEXT_DIR}"
[ -f "$SEALED" ] || { echo "ERROR: sealed image not found: $SEALED" >&2; exit 1; }

mkdir -p "$CTX"
cp "$SEALED" "$CTX/win98.qcow2.builtin"

cat > "$CTX/Dockerfile" <<'EOF'
# Carrier image for the Win98 + Lego Loco golden qcow2. Data-only; the
# embedded qcow2 is architecture-neutral, so build --platform for both arches.
FROM scratch
COPY win98.qcow2.builtin /opt/builtin-images/win98.qcow2.builtin
EOF

cat > "$CTX/README.txt" <<EOF
Build + push multi-arch:

  docker buildx build \\
    --platform linux/amd64,linux/arm64 \\
    -t ghcr.io/mroie/lego-loco-cluster/win98-loco-golden:safe512-v1 \\
    --push "$CTX"

Consumers copy /opt/builtin-images/win98.qcow2.builtin out of the image.
EOF

echo "[oci] context staged at $CTX"
ls -la "$CTX"
