# PCem emulator container — real Socket 7 / i430VX hardware emulation with a
# 3dfx Voodoo3 3000, running Windows 98 SE + LEGO LOCO, rendered into a
# headless X server and exposed to the cluster as plain VNC on :5901.
#
# Everything here follows the bring-up log in `standalone/README.md`; the
# gotcha numbers in the comments below refer to that file.

########################################################################
# Stage 1 — build PCem v17 from the official source release.
#
# gotcha #1: no prebuilt Linux binary exists. The release asset is an
# autotools source tarball, and OpenAL is a hard build dependency.
########################################################################
FROM debian:bookworm-slim AS builder

ARG PCEM_TARBALL=https://github.com/sarah-walker-pcem/pcem/releases/download/v17/PCemV17Linux.tar.gz

# gotcha #9: `--enable-release-build` (-O3 -DRELEASE_BUILD) miscompiles the
# IDE disk-detection path — every boot ends in "Primary master hard disk
# fail". The -O0 debug build detects the same disk correctly every time, and
# still holds 100–101% of real Pentium-MMX-200 speed because the hot path is
# dynarec-generated code rather than compiler output (see the benchmark table
# in standalone/README.md). Networking pulls in PCem's bundled SLiRP stack —
# no extra system libraries.
ARG PCEM_CONFIGURE_FLAGS="--enable-debug --enable-alsa --enable-networking"

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential pkg-config ca-certificates curl python3 \
        libsdl2-dev libwxgtk3.2-dev libasound2-dev libopenal-dev libpcap-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN curl -fsSL "$PCEM_TARBALL" | tar xz

# Upstream PCem grabs and warps the host pointer, which is unusable when the
# pointer is being driven remotely by a VNC client. See patches/vnc-mouse.py.
COPY patches/vnc-mouse.py /tmp/vnc-mouse.py
RUN python3 /tmp/vnc-mouse.py /src

# Upstream compiles the bridged (PCap) network backend only #ifdef _WIN32 and
# hard-codes SLiRP on Linux. SLiRP is host-NAT, so two instances cannot see
# each other — which rules out a LAN game. See patches/linux-pcap.py.
COPY patches/linux-pcap.py /tmp/linux-pcap.py
RUN python3 /tmp/linux-pcap.py /src

RUN ./configure ${PCEM_CONFIGURE_FLAGS} LIBS="-lpcap" \
    && make -j"$(nproc)" \
    && install -Dm755 "$(find . -maxdepth 2 -type f -executable -name pcem | head -1)" /out/pcem \
    && /out/pcem --help >/dev/null 2>&1 || true

# Resolve the exact runtime library packages from the linked binary rather
# than hardcoding Debian package names that drift between releases.
#
# ldd reports some libraries under /lib/... while dpkg's database records them
# under /usr/lib/... (/lib is a compat symlink), so resolve real paths first —
# otherwise `dpkg -S` misses them and the runtime image ships without, say,
# libopenal.so.1. Any unresolvable library fails the build rather than
# producing an image that dies on first start.
RUN set -eu; \
    ldd /out/pcem | awk '/=> \//{print $3}' | sort -u > /out/libs.txt; \
    : > /out/runtime-deps.txt; \
    while read -r lib; do \
      real="$(readlink -f "$lib")"; \
      pkg=""; \
      for cand in "$lib" "$real" "${real#/usr}" "/usr${lib}"; do \
        pkg="$(dpkg -S "$cand" 2>/dev/null | cut -d: -f1 | head -1)"; \
        [ -n "$pkg" ] && break; \
      done; \
      [ -n "$pkg" ] || { echo "no package owns $lib" >&2; exit 1; }; \
      echo "$pkg" >> /out/runtime-deps.txt; \
    done < /out/libs.txt; \
    sort -u -o /out/runtime-deps.txt /out/runtime-deps.txt; \
    cat /out/runtime-deps.txt

# PCem ships default CMOS contents for the machines it knows about; copy them
# so a fresh container starts from a sane NVRAM rather than an empty one.
RUN cp -r /src/nvr /out/nvr

########################################################################
# Stage 2 — fetch the two BIOS dumps PCem needs.
#
# gotcha #2: PCem ships only `roms.txt` placeholders. The dumps it expects
# byte-for-byte are in the 86Box community ROM set under different letter
# case, so they are renamed to the names `mem_bios.c` /
# `vid_voodoo_banshee.c` actually call `romfopen()` with.
########################################################################
FROM debian:bookworm-slim AS roms

ARG ROM_BASE=https://raw.githubusercontent.com/86Box/roms/master

RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Both Socket 7 boards are shipped: Windows 98 binds chipset drivers at install
# time, so the guest has to boot on the same board it was installed on or it
# comes up in a PnP re-detect storm (VGA fallback, dead mouse, "New Hardware
# Found"). The LEGO LOCO snapshot was installed on the FIC VA-503+.
RUN mkdir -p /roms/430vx /roms/fic_va503p /roms/voodoo3_3000 \
    && curl -fsSL -o /roms/430vx/55xwuq0e.bin      "${ROM_BASE}/machines/430vx/55XWUQ0E.BIN" \
    && curl -fsSL -o /roms/fic_va503p/je4333.bin   "${ROM_BASE}/machines/ficva503p/je4333.bin" \
    && curl -fsSL -o /roms/voodoo3_3000/3k12sd.rom "${ROM_BASE}/video/voodoo/3k12sd.rom" \
    && [ "$(stat -c%s /roms/430vx/55xwuq0e.bin)"      = 131072 ] \
    && [ "$(stat -c%s /roms/fic_va503p/je4333.bin)"   = 131072 ] \
    && [ "$(stat -c%s /roms/voodoo3_3000/3k12sd.rom)" = 65536 ]

########################################################################
# Stage 3 — runtime.
########################################################################
FROM debian:bookworm-slim

LABEL org.opencontainers.image.title="lego-loco PCem emulator" \
      org.opencontainers.image.description="PCem v17 (i430VX + Voodoo3 3000) running Windows 98 SE + LEGO LOCO, exposed over VNC" \
      org.opencontainers.image.source="https://github.com/MRoie/lego-loco-cluster"

COPY --from=builder /out/runtime-deps.txt /tmp/runtime-deps.txt

RUN apt-get update && apt-get install -y --no-install-recommends \
        $(cat /tmp/runtime-deps.txt) \
        tigervnc-standalone-server xvfb x11vnc xdotool x11-utils \
        python3 curl ca-certificates procps tini mtools iproute2 ethtool libpcap0.8 dnsmasq \
    && rm -rf /var/lib/apt/lists/* /tmp/runtime-deps.txt

COPY --from=builder /out/pcem /usr/local/bin/pcem
COPY --from=builder /out/nvr  /opt/pcem/nvr-defaults
COPY --from=roms    /roms     /opt/pcem/roms
# Known-good CMOS per board, so a pod with a fresh disk volume boots without
# stopping on the BIOS's "Press F1 to continue".
COPY nvr-seed/ /opt/pcem/nvr-seed/

# Fail the build, not the first boot, if a shared library did not make it in.
RUN ldd /usr/local/bin/pcem | grep -F "not found" && exit 1 || true

COPY entrypoint.sh /entrypoint.sh
COPY scripts/ /usr/local/bin/
RUN chmod +x /entrypoint.sh /usr/local/bin/pull-snapshot.sh /usr/local/bin/health-server.py

# gotcha #3: on Linux PCem's config/ROM root is $HOME/.pcem, taken from
# wxFileName::GetHomeDir() unconditionally — never the executable's own
# directory. HOME must therefore be writable.
ENV HOME=/pcem \
    DISPLAY=:99 \
    SCREEN_WIDTH=1024 \
    SCREEN_HEIGHT=768 \
    VNC_PORT=5901 \
    HEALTH_PORT=8080 \
    DISK_DIR=/images \
    DISK_NAME=win98-loco.vhd \
    SNAPSHOT_IMAGE=ghcr.io/mroie/lego-loco-cluster/emulator-snapshot:pcem-win98-loco-1024x768

RUN mkdir -p /pcem /images /config && chmod 777 /pcem /images

VOLUME ["/images"]
EXPOSE 5901 8080

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
