#!/bin/bash
# Build PCem v17 (official sarah-walker-pcem/pcem Linux source release) under /work (G:).
set -eux
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
  build-essential pkg-config \
  libsdl2-dev libwxgtk3.2-dev libasound2-dev libopenal-dev \
  ca-certificates

cd /work
./configure --enable-release-build --enable-alsa
make -j"$(nproc)"
echo "=== binaries ==="
find . -maxdepth 1 -type f -executable -name "PCem*" -o -maxdepth 1 -type f -executable -name "pcem*"
echo "BUILD_OK"
