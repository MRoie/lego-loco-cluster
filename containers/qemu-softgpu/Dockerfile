# Stage 1: Extract win98 image from the public container
FROM ghcr.io/mroie/lego-loco-cluster/win98-softgpu:latest AS win98-extractor
# The win98_softgpu.qcow2 file is already in the /vm directory of this image

# Stage 2: Build the final emulator container
FROM ubuntu:22.04

# ---- Install emulator and media tools ----
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    qemu-system-x86 qemu-system-gui qemu-utils pulseaudio \
    gstreamer1.0-tools gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly gstreamer1.0-libav \
    gstreamer1.0-plugins-base gstreamer1.0-pulseaudio libopus-dev \
    x11-utils xdotool iproute2 xvfb net-tools \
    curl wget skopeo git inotify-tools nfs-common rsync \
    iputils-ping tcpdump genisoimage \
    netcat-openbsd procps alsa-utils dosfstools mtools \
    libhivex-bin python3-hivex && \
    rm -rf /var/lib/apt/lists/*

# ---- Create images directory and copy win98 image at build time ----
RUN mkdir -p /images /opt/builtin-images
COPY --from=win98-extractor /opt/builtin-images/win98.qcow2.builtin /opt/builtin-images/win98.qcow2.builtin

# ---- Copy SoftGPU ISO for VMware SVGA driver installation ----
COPY softgpu.iso /opt/softgpu.iso

# ---- Copy entrypoint and scripts ----
COPY entrypoint.sh /entrypoint.sh
COPY customize-win98-instance.sh /usr/local/bin/customize-win98-instance.sh
COPY mini_dhcp.py /usr/local/bin/mini_dhcp.py
COPY watch_art_res.sh /usr/local/bin/watch_art_res.sh
COPY health-monitor.sh /usr/local/bin/health-monitor.sh
RUN chmod +x /entrypoint.sh /usr/local/bin/customize-win98-instance.sh /usr/local/bin/mini_dhcp.py /usr/local/bin/watch_art_res.sh /usr/local/bin/health-monitor.sh

# ---- Verify the disk image is available ----
RUN ls -la /opt/builtin-images/ && \
    qemu-img info /opt/builtin-images/win98.qcow2.builtin && \
    echo "✅ Win98 disk image successfully copied at build time"

# ---- Expose health monitoring port ----
EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
