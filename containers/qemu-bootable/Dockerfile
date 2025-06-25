FROM ubuntu:22.04

# Install required packages
RUN apt-get update && \
    apt-get install -y -q \
    qemu-system-x86 \
    qemu-utils \
    xvfb \
    x11vnc \
    pulseaudio \
    gstreamer1.0-tools \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-x \
    x264 \
    iproute2 \
    net-tools \
    wget \
    curl \
    unzip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy entrypoint script
COPY entrypoint-bootable.sh /entrypoint-bootable.sh
RUN chmod +x /entrypoint-bootable.sh

# Create directories
RUN mkdir -p /images /snapshots

EXPOSE 5901 6080 5000

ENTRYPOINT ["/entrypoint-bootable.sh"]
