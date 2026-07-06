ARG QEMU_VERSION=9.2.2
ARG QEMU_3DFX_REPO=https://github.com/kjliew/qemu-3dfx.git
ARG QEMU_3DFX_REF=master
ARG RUNTIME_BASE=qemu-loco-softgpu:v27-softgpu-perf

# Stage 1: Build a QEMU with qemu-3dfx/Mesa pass-through support
FROM ubuntu:22.04 AS qemu3dfx-builder

ARG QEMU_VERSION
ARG QEMU_3DFX_REPO
ARG QEMU_3DFX_REF

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates wget git rsync patch build-essential ninja-build \
    python3 python3-venv python3-tomli pkg-config \
    libglib2.0-dev libpixman-1-dev zlib1g-dev \
    libsdl2-dev libepoxy-dev libslirp-dev libpulse-dev \
    libpng-dev libjpeg-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /build
RUN set -eux; \
    git clone --depth 1 "${QEMU_3DFX_REPO}" qemu-3dfx; \
    cd qemu-3dfx; \
    if [ "${QEMU_3DFX_REF}" != "master" ]; then \
      git fetch --depth 1 origin "${QEMU_3DFX_REF}"; \
      git checkout FETCH_HEAD; \
    fi; \
    git rev-parse --short=7 HEAD > /tmp/qemu3dfx.rev; \
    cd /build; \
    wget -q "https://download.qemu.org/qemu-${QEMU_VERSION}.tar.xz"; \
    tar xf "qemu-${QEMU_VERSION}.tar.xz"; \
    cd "qemu-${QEMU_VERSION}"; \
    rsync -r ../qemu-3dfx/qemu-0/hw/3dfx ../qemu-3dfx/qemu-1/hw/mesa ./hw/; \
    patch -p0 -i "../qemu-3dfx/00-qemu92x-mesa-glide.patch"; \
    sed -i \
      -e 's/SDL_ResetHint(SDL_HINT_RENDER_DRIVER);/SDL_SetHint(SDL_HINT_RENDER_DRIVER, "");/' \
      -e 's/SDL_HINT_VIDEODRIVER/"SDL_VIDEODRIVER"/g' \
      ui/sdl2.c; \
    bash ../qemu-3dfx/scripts/sign_commit -git=../qemu-3dfx; \
    mkdir /build/qemu-build; \
    cd /build/qemu-build; \
    CFLAGS="-O2 -msse4.2" "../qemu-${QEMU_VERSION}/configure" \
      --prefix=/opt/qemu-3dfx \
      --target-list=i386-softmmu \
      --enable-sdl \
      --enable-opengl \
      --enable-kvm \
      --enable-slirp \
      --enable-vnc; \
    make -j"$(nproc)"; \
    make install; \
    cp /tmp/qemu3dfx.rev /opt/qemu-3dfx/REV_QEMU3DFX; \
    find /opt/qemu-3dfx/bin /opt/qemu-3dfx/libexec -type f -executable -exec strip --strip-unneeded {} + || true; \
    rm -f \
      /opt/qemu-3dfx/share/qemu/edk2-aarch64-* \
      /opt/qemu-3dfx/share/qemu/edk2-arm-* \
      /opt/qemu-3dfx/share/qemu/edk2-riscv-* \
      /opt/qemu-3dfx/share/qemu/edk2-loongarch64-* \
      /opt/qemu-3dfx/share/qemu/openbios-* \
      /opt/qemu-3dfx/share/qemu/hppa-* \
      /opt/qemu-3dfx/share/qemu/slof.bin \
      /opt/qemu-3dfx/share/qemu/skiboot.lid \
      /opt/qemu-3dfx/share/qemu/u-boot* \
      /opt/qemu-3dfx/share/qemu/opensbi-* \
      /opt/qemu-3dfx/share/qemu/palcode-* \
      /opt/qemu-3dfx/share/qemu/s390-*; \
    du -sh /opt/qemu-3dfx; \
    /opt/qemu-3dfx/bin/qemu-system-i386 --version

# Stage 2: Build the final emulator container from the current working runtime
FROM ${RUNTIME_BASE}

# ---- Add only the runtime piece missing from the current image ----
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    x11vnc && \
    rm -rf /var/lib/apt/lists/*

# ---- Copy patched QEMU for qemu-3dfx / Mesa pass-through mode ----
COPY --from=qemu3dfx-builder /opt/qemu-3dfx /opt/qemu-3dfx

# ---- Copy entrypoint and scripts ----
COPY entrypoint.sh /entrypoint.sh
COPY customize-win98-instance.sh /usr/local/bin/customize-win98-instance.sh
COPY mini_dhcp.py /usr/local/bin/mini_dhcp.py
COPY qmp-control.py /usr/local/bin/qmp-control.py
COPY watch_art_res.sh /usr/local/bin/watch_art_res.sh
COPY health-monitor.sh /usr/local/bin/health-monitor.sh
COPY setup-lan-network.sh /usr/local/bin/setup-lan-network.sh
RUN sed -i 's/\r$//' /entrypoint.sh /usr/local/bin/customize-win98-instance.sh /usr/local/bin/mini_dhcp.py /usr/local/bin/qmp-control.py /usr/local/bin/watch_art_res.sh /usr/local/bin/health-monitor.sh /usr/local/bin/setup-lan-network.sh && \
    chmod +x /entrypoint.sh /usr/local/bin/customize-win98-instance.sh /usr/local/bin/mini_dhcp.py /usr/local/bin/qmp-control.py /usr/local/bin/watch_art_res.sh /usr/local/bin/health-monitor.sh /usr/local/bin/setup-lan-network.sh

# ---- Verify the disk image is available ----
RUN ls -la /opt/builtin-images/ && \
    /opt/qemu-3dfx/bin/qemu-img info /opt/builtin-images/win98.qcow2.builtin && \
    /opt/qemu-3dfx/bin/qemu-system-i386 --version && \
    echo "✅ Win98 disk image successfully copied at build time"

# ---- Expose health monitoring port ----
EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
