#!/usr/bin/env bash
# ============================================================================
# push-golden-image.sh — build OCI carriers from the clean golden qcow2 and
# push them to GHCR. (bash port of push-golden-image.ps1)
# ============================================================================
# GHCR needs a CLASSIC PAT with `write:packages`. The gho_ OAuth token in Git
# Credential Manager (scopes gist/repo/workflow) CANNOT push — create a classic
# token at GitHub > Settings > Developer settings > Personal access tokens
# (classic) with write:packages (+ repo), then:
#
#   export GHCR_TOKEN=ghp_xxx
#   scripts/push-golden-image.sh                 # golden + cluster tags
#   scripts/push-golden-image.sh --multi-arch    # amd64+arm64 (buildx)
#   scripts/push-golden-image.sh --golden-only
#   scripts/push-golden-image.sh --skip-login    # already docker-logged-in
# ============================================================================
set -euo pipefail

QCOW2="containers/win98-loco-golden-safe512.qcow2"
USER_NAME="MRoie"
GOLDEN_TAG="ghcr.io/mroie/lego-loco-cluster/win98-loco-golden:safe512-v1"
SNAPSHOT_TAGS=(
  "ghcr.io/mroie/lego-loco-cluster/emulator-snapshot:hostgame"
  "ghcr.io/mroie/lego-loco-cluster/emulator-snapshot:joingame"
  "ghcr.io/mroie/lego-loco-cluster/emulator-snapshot:clean-safe512"
)
MULTI_ARCH=0; GOLDEN_ONLY=0; SKIP_LOGIN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --qcow2) QCOW2="$2"; shift 2;;
    --multi-arch) MULTI_ARCH=1; shift;;
    --golden-only) GOLDEN_ONLY=1; shift;;
    --skip-login) SKIP_LOGIN=1; shift;;
    *) echo "Unknown option: $1" >&2; exit 2;;
  esac
done

cd "$(dirname "$0")/.."
[ -f "$QCOW2" ] || { echo "ERROR: qcow2 not found: $QCOW2" >&2; exit 1; }
echo "Payload: $QCOW2 ($(stat -c %s "$QCOW2" 2>/dev/null || wc -c < "$QCOW2") bytes)"

if [ "$SKIP_LOGIN" != 1 ]; then
  if [ -z "${GHCR_TOKEN:-}" ]; then
    echo "ERROR: set GHCR_TOKEN to a classic PAT with write:packages, or use --skip-login after 'docker login ghcr.io'." >&2
    exit 1
  fi
  echo "$GHCR_TOKEN" | docker login ghcr.io -u "$USER_NAME" --password-stdin
fi

CTX="$(mktemp -d)"
trap 'rm -rf "$CTX"' EXIT
cp "$QCOW2" "$CTX/payload.qcow2"

push_carrier() {
  local tag="$1" dest="$2"
  printf 'FROM scratch\nCOPY payload.qcow2 %s\n' "$dest" > "$CTX/Dockerfile"
  if [ "$MULTI_ARCH" = 1 ]; then
    echo "=== buildx push (amd64+arm64): $tag ==="
    docker buildx build --platform linux/amd64,linux/arm64 -t "$tag" --push "$CTX"
  else
    echo "=== build + push (amd64): $tag ==="
    docker build -t "$tag" "$CTX"
    docker push "$tag"
  fi
}

# Android golden: builtin path expected by the emulator/golden-image runtime.
push_carrier "$GOLDEN_TAG" "/opt/builtin-images/win98.qcow2.builtin"

# Cluster snapshot tags: qcow2 at root named <tag>.qcow2.
if [ "$GOLDEN_ONLY" != 1 ]; then
  for t in "${SNAPSHOT_TAGS[@]}"; do
    name="${t##*:}"
    push_carrier "$t" "/${name}.qcow2"
  done
fi

echo "=== DONE ==="
echo "Pushed: $GOLDEN_TAG"
[ "$GOLDEN_ONLY" = 1 ] || printf '        %s\n' "${SNAPSHOT_TAGS[@]}"
