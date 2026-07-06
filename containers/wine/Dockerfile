# Base image
FROM ubuntu:22.04

# ---- Enable i386 and install Wine with streaming tools ----
RUN dpkg --add-architecture i386 && apt-get update && \
    apt-get install -y --no-install-recommends \
        wine winbind pulseaudio \
        gstreamer1.0-tools gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
        x11-utils xdotool && \
    rm -rf /var/lib/apt/lists/*

# ---- Copy entrypoint ----
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
