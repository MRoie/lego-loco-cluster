# Base image
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

# ---- Copy entrypoint ----
COPY entrypoint.sh /entrypoint.sh
COPY watch_art_res.sh /usr/local/bin/watch_art_res.sh
COPY health-monitor.sh /usr/local/bin/health-monitor.sh
RUN chmod +x /entrypoint.sh /usr/local/bin/watch_art_res.sh /usr/local/bin/health-monitor.sh

# ---- Expose health monitoring port ----
EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
