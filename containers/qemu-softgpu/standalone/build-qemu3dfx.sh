#!/bin/bash
# Build qemu-3dfx (QEMU 9.2.2 + Mesa/Glide passthrough) entirely under /work (G:).
set -eux
export DEBIAN_FRONTEND=noninteractive

QEMU_VERSION=9.2.2
QEMU_3DFX_REPO=https://github.com/kjliew/qemu-3dfx.git

echo "=== [1/5] apt deps (build + headless-GL runtime) ==="
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates wget git rsync patch build-essential ninja-build \
  python3 python3-venv python3-pip pkg-config \
  libglib2.0-dev libpixman-1-dev zlib1g-dev \
  libsdl2-dev libepoxy-dev libslirp-dev libpulse-dev \
  libpng-dev libjpeg-dev flex bison \
  xvfb x11vnc mesa-utils libgl1-mesa-dri libglx-mesa0 xauth net-tools procps

cd /work

echo "=== [2/5] fetch qemu-3dfx + qemu source ==="
[ -d qemu-3dfx ] || git clone --depth 1 "$QEMU_3DFX_REPO" qemu-3dfx
[ -f qemu-${QEMU_VERSION}.tar.xz ] || wget -q "https://download.qemu.org/qemu-${QEMU_VERSION}.tar.xz"
rm -rf qemu-${QEMU_VERSION}
tar xf qemu-${QEMU_VERSION}.tar.xz

echo "=== [3/5] apply 3dfx/mesa passthrough patch ==="
cd qemu-${QEMU_VERSION}
rsync -r ../qemu-3dfx/qemu-0/hw/3dfx ../qemu-3dfx/qemu-1/hw/mesa ./hw/
patch -p0 -i ../qemu-3dfx/00-qemu92x-mesa-glide.patch
sed -i \
  -e 's/SDL_ResetHint(SDL_HINT_RENDER_DRIVER);/SDL_SetHint(SDL_HINT_RENDER_DRIVER, "");/' \
  -e 's/SDL_HINT_VIDEODRIVER/"SDL_VIDEODRIVER"/g' \
  ui/sdl2.c || true
bash ../qemu-3dfx/scripts/sign_commit -git=../qemu-3dfx || true

echo "=== [4/5] configure + make (this is the long part) ==="
rm -rf /work/qemu-build && mkdir -p /work/qemu-build
cd /work/qemu-build
CFLAGS="-O2 -msse4.2" ../qemu-${QEMU_VERSION}/configure \
  --prefix=/work/opt/qemu-3dfx \
  --target-list=i386-softmmu \
  --enable-sdl --enable-opengl --enable-slirp --enable-vnc
make -j"$(nproc)"
make install

echo "=== [5/5] done ==="
/work/opt/qemu-3dfx/bin/qemu-system-i386 --version
du -sh /work/opt/qemu-3dfx
echo "BUILD_OK"
