FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    qemu-kvm qemu-system-x86 \
    iproute2 iputils-ping bridge-utils \
    x11vnc websockify xvfb novnc \
    net-tools sudo curl unzip && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /vm

# Debug: Show build context and current directory (force rebuild with timestamp)
RUN echo "=== BUILD CONTEXT DEBUG $(date) ===" && \
    pwd && \
    echo "Current directory contents:" && \
    ls -la && \
    echo "Looking for qcow2 files:" && \
    find . -name "*.qcow2" -ls 2>/dev/null || echo "No qcow2 files found in current directory" && \
    echo "Looking for any large files (>100MB):" && \
    find . -size +100M -ls 2>/dev/null || echo "No large files found" && \
    echo "=== END DEBUG ==="

# Copy qemu manager script
COPY qemu-manager.sh /usr/local/bin/qemu-manager.sh
RUN chmod +x /usr/local/bin/qemu-manager.sh

# Copy the downloaded Win98 VM image
COPY win98_softgpu.qcow2 /vm/win98_softgpu.qcow2

# Debug: Verify the file was copied
RUN echo "=== VM IMAGE VERIFICATION ===" && \
    ls -la /vm/ && \
    echo "VM image info:" && \
    qemu-img info /vm/win98_softgpu.qcow2

# Set working directory where the VM image is expected
WORKDIR /vm

VOLUME ["/shared"]
EXPOSE 6080 2300 47624

ENTRYPOINT ["/usr/local/bin/qemu-manager.sh"]
CMD ["run"]
