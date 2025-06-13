# Base image
FROM ubuntu:22.04

# ---- Install PCem emulator and streaming tools ----
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        pcem pulseaudio \
        gstreamer1.0-tools gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
        x11-utils xdotool && \
    rm -rf /var/lib/apt/lists/*

# ---- Copy entrypoint ----
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
