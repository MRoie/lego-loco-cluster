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
        x11-utils xdotool iproute2 xvfb net-tools \
        curl wget skopeo git inotify-tools nfs-common rsync \
        netcat-openbsd procps alsa-utils && \
    rm -rf /var/lib/apt/lists/*

# ---- Create images directory and copy win98 image at build time ----
RUN mkdir -p /images
COPY --from=win98-extractor /vm/win98_softgpu.qcow2 /images/win98.qcow2

# ---- Copy entrypoint and scripts ----
COPY entrypoint.sh /entrypoint.sh
COPY watch_art_res.sh /usr/local/bin/watch_art_res.sh
COPY health-monitor.sh /usr/local/bin/health-monitor.sh
RUN chmod +x /entrypoint.sh /usr/local/bin/watch_art_res.sh /usr/local/bin/health-monitor.sh

# ---- Verify the disk image is available ----
RUN ls -la /images/ && \
    qemu-img info /images/win98.qcow2 && \
    echo "✅ Win98 disk image successfully copied at build time"

# ---- Expose health monitoring port ----
EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
