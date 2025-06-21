FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    qemu-kvm qemu-system-x86 \
    iproute2 iputils-ping bridge-utils \
    x11vnc websockify xvfb novnc \
    net-tools sudo curl unzip && \
    rm -rf /var/lib/apt/lists/*

COPY win98_softgpu.qcow2 /vm/win98_softgpu.qcow2
COPY qemu-manager.sh /usr/local/bin/qemu-manager.sh

RUN chmod +x /usr/local/bin/qemu-manager.sh

# Set working directory where the VM image is expected
WORKDIR /vm

VOLUME ["/shared"]
EXPOSE 6080 2300 47624

ENTRYPOINT ["/usr/local/bin/qemu-manager.sh"]
CMD ["run"]
