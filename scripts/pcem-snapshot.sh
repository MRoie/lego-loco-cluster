#!/usr/bin/env bash
# Package a PCem guest disk as an OCI image, the same shape as the existing
# ghcr.io/mroie/lego-loco-cluster/emulator-snapshot:* tags — a scratch image
# whose single layer is the disk file. `containers/pcem/scripts/pull-snapshot.sh`
# fetches exactly this with plain curl.
#
#   scripts/pcem-snapshot.sh <disk.vhd> <tag> [--load-kind CLUSTER] [--push]
#
#   scripts/pcem-snapshot.sh /path/win98-loco-net.vhd \
#       ghcr.io/mroie/lego-loco-cluster/emulator-snapshot:pcem-win98-loco-net \
#       --load-kind loco
#
# --load-kind also seeds the node's snapshot cache, so pods start from a local
# copy instead of pulling ~500 MB each. --push needs `docker login ghcr.io`.
set -euo pipefail

DISK="${1:?usage: pcem-snapshot.sh <disk.vhd> <tag> [--load-kind CLUSTER] [--push]}"
TAG="${2:?usage: pcem-snapshot.sh <disk.vhd> <tag> [--load-kind CLUSTER] [--push]}"
shift 2

KIND_CLUSTER=""
PUSH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --load-kind) KIND_CLUSTER="${2:?--load-kind needs a cluster name}"; shift 2 ;;
    --push)      PUSH=1; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done

[ -f "$DISK" ] || { echo "no such disk: $DISK" >&2; exit 1; }

DISK_NAME="$(basename "$DISK")"
CTX="$(mktemp -d)"
trap 'rm -rf "$CTX"' EXIT

# Hardlink if we can — these images are ~500 MB and copying them twice is a
# noticeable part of the build.
ln "$DISK" "${CTX}/${DISK_NAME}" 2>/dev/null || cp "$DISK" "${CTX}/${DISK_NAME}"

cat > "${CTX}/Dockerfile" <<EOF
FROM scratch
COPY ${DISK_NAME} /${DISK_NAME}
EOF

echo "==> building ${TAG} from ${DISK_NAME} ($(stat -c%s "$DISK") bytes)"
docker build -q -t "$TAG" "$CTX" >/dev/null
echo "==> built ${TAG}"

if [ -n "$KIND_CLUSTER" ]; then
  NODE="${KIND_CLUSTER}-control-plane"
  echo "==> seeding snapshot cache on ${NODE}"
  docker exec "$NODE" mkdir -p /var/lib/loco/snapshot-cache
  docker cp "$DISK" "${NODE}:/var/lib/loco/snapshot-cache/${DISK_NAME}"
  docker exec "$NODE" ls -la /var/lib/loco/snapshot-cache/
fi

if [ "$PUSH" = "1" ]; then
  echo "==> pushing ${TAG}"
  docker push "$TAG"
fi

echo "done"
