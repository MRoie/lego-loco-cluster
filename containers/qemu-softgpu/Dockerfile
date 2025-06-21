FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    qemu-kvm qemu-system-x86 \
    iproute2 iputils-ping bridge-utils \
    x11vnc websockify xvfb novnc \
    net-tools sudo curl unzip && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /vm

# Debug: Show build context and current directory
RUN echo "=== BUILD CONTEXT DEBUG ===" && \
    pwd && \
    echo "Current directory contents:" && \
    ls -la && \
    echo "Looking for qcow2 files:" && \
    find . -name "*.qcow2" -ls 2>/dev/null || echo "No qcow2 files found in current directory"

# Copy qemu manager script
COPY qemu-manager.sh /usr/local/bin/qemu-manager.sh
RUN chmod +x /usr/local/bin/qemu-manager.sh

# Copy the actual VM image file (not placeholder)
COPY win98_softgpu.qcow2 /vm/win98_softgpu.qcow2

# Debug: Verify the file was copied
RUN echo "=== VM IMAGE VERIFICATION ===" && \
    ls -la /vm/ && \
    if [ -f "/vm/win98_softgpu.qcow2" ]; then \
        echo "VM image copied successfully: $(du -h /vm/win98_softgpu.qcow2)"; \
    else \
        echo "ERROR: VM image not found after copy"; \
        exit 1; \
    fi

# Set working directory where the VM image is expected
WORKDIR /vm

VOLUME ["/shared"]
EXPOSE 6080 2300 47624

ENTRYPOINT ["/usr/local/bin/qemu-manager.sh"]
CMD ["run"]
