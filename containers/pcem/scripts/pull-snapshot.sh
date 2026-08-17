#!/usr/bin/env bash
# Pull a disk image out of an OCI image using nothing but curl and tar.
#
# The emulator snapshots (ghcr.io/mroie/lego-loco-cluster/emulator-snapshot:*)
# are single-layer images whose only payload is the disk file. Rather than
# shipping skopeo/crane into every emulator container just to fetch one blob,
# this talks the registry v2 API directly — the same approach the Android
# Loco Lens bundle uses, and one less binary in the image.
#
# Usage: pull-snapshot.sh <image-ref> <target-file>
#   image-ref: [registry/]repo:tag   (defaults to ghcr.io)
#
# Private repositories: set REGISTRY_USER + REGISTRY_TOKEN (a GitHub PAT with
# read:packages for ghcr.io).
set -euo pipefail

IMAGE_REF="${1:?usage: pull-snapshot.sh <image-ref> <target-file>}"
TARGET="${2:?usage: pull-snapshot.sh <image-ref> <target-file>}"

log() { echo "[pull-snapshot] $*"; }
die() { echo "[pull-snapshot] ERROR: $*" >&2; exit 1; }

# ---- split registry / repo / tag -------------------------------------------
ref="$IMAGE_REF"
case "$ref" in
  */*)
    first="${ref%%/*}"
    case "$first" in
      *.*|*:*|localhost) REGISTRY="$first"; ref="${ref#*/}" ;;
      *)                 REGISTRY="ghcr.io" ;;
    esac
    ;;
  *) REGISTRY="ghcr.io" ;;
esac

case "$ref" in
  *:*) REPO="${ref%:*}"; TAG="${ref##*:}" ;;
  *)   REPO="$ref";      TAG="latest" ;;
esac

log "registry=${REGISTRY} repo=${REPO} tag=${TAG}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---- auth ------------------------------------------------------------------
AUTH_URL="https://${REGISTRY}/token?scope=repository:${REPO}:pull&service=${REGISTRY}"
if [ -n "${REGISTRY_TOKEN:-}" ]; then
  TOKEN="$(curl -fsSL -u "${REGISTRY_USER:-x}:${REGISTRY_TOKEN}" "$AUTH_URL" \
             | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
else
  TOKEN="$(curl -fsSL "$AUTH_URL" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
fi
[ -n "$TOKEN" ] || die "could not obtain a pull token for ${REPO}"

api() { curl -fsSL -H "Authorization: Bearer ${TOKEN}" "$@"; }

ACCEPT='Accept: application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json,application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json'

# ---- manifest (following a manifest list if we got one) --------------------
MANIFEST="${WORK}/manifest.json"
api -H "$ACCEPT" "https://${REGISTRY}/v2/${REPO}/manifests/${TAG}" -o "$MANIFEST" \
  || die "failed to fetch manifest for ${REPO}:${TAG}"

if grep -q '"manifests"' "$MANIFEST"; then
  log "manifest list — selecting linux/amd64"
  CHILD="$(tr ',' '\n' < "$MANIFEST" \
            | grep -B4 '"architecture": *"amd64"' \
            | sed -n 's/.*"digest": *"\([^"]*\)".*/\1/p' | head -1)"
  [ -n "$CHILD" ] || CHILD="$(sed -n 's/.*"digest": *"\(sha256:[^"]*\)".*/\1/p' "$MANIFEST" | head -1)"
  api -H "$ACCEPT" "https://${REGISTRY}/v2/${REPO}/manifests/${CHILD}" -o "$MANIFEST" \
    || die "failed to fetch child manifest ${CHILD}"
fi

# ---- layers ----------------------------------------------------------------
LAYERS="$(sed -n 's/.*"digest": *"\(sha256:[^"]*\)".*/\1/p' "$MANIFEST")"
CONFIG_DIGEST="$(tr -d ' \n' < "$MANIFEST" | sed -n 's/.*"config":{[^}]*"digest":"\(sha256:[^"]*\)".*/\1/p')"

EXTRACT="${WORK}/extract"
mkdir -p "$EXTRACT"

for digest in $LAYERS; do
  [ "$digest" = "$CONFIG_DIGEST" ] && continue
  log "fetching layer ${digest%%:*}:${digest#*:}"
  api "https://${REGISTRY}/v2/${REPO}/blobs/${digest}" -o "${WORK}/layer.tgz" \
    || die "failed to fetch blob ${digest}"
  # Layers are gzipped tars; a few registries serve them uncompressed.
  tar -xzf "${WORK}/layer.tgz" -C "$EXTRACT" 2>/dev/null \
    || tar -xf "${WORK}/layer.tgz" -C "$EXTRACT" \
    || die "layer ${digest} is not a tar archive"
  rm -f "${WORK}/layer.tgz"
done

# ---- pick out the disk -----------------------------------------------------
DISK="$(find "$EXTRACT" -type f \( -name '*.vhd' -o -name '*.img' -o -name '*.qcow2' -o -name '*.raw' \) \
          -printf '%s\t%p\n' 2>/dev/null | sort -rn | head -1 | cut -f2)"
if [ -z "$DISK" ]; then
  DISK="$(find "$EXTRACT" -type f -printf '%s\t%p\n' | sort -rn | head -1 | cut -f2)"
fi
[ -n "$DISK" ] || die "no disk image found inside ${IMAGE_REF}"

log "extracted $(basename "$DISK") ($(stat -c%s "$DISK") bytes)"
mkdir -p "$(dirname "$TARGET")"
# Same filesystem is not guaranteed (tmpdir vs PVC), so copy then rename.
cp "$DISK" "${TARGET}.partial"
mv "${TARGET}.partial" "$TARGET"
log "wrote ${TARGET}"
