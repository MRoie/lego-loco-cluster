# Base image
FROM ubuntu:22.04

# ---- Install emulator and media tools ----
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        qemu-system-x86 qemu-system-gui pulseaudio \
        gstreamer1.0-tools gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
        gstreamer1.0-plugins-ugly gstreamer1.0-libav \
        x11-utils xdotool iproute2 xvfb && \
    rm -rf /var/lib/apt/lists/*

# ---- Copy entrypoint ----
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
