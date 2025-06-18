FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    qemu-kvm qemu-system-x86 \
    iproute2 iputils-ping bridge-utils \
    x11vnc websockify xvfb novnc \
    net-tools sudo curl unzip && \
    rm -rf /var/lib/apt/lists/*

COPY win98_softgpu.qcow2 /vm/win98.qcow2
COPY run-qemu.sh /usr/local/bin/run-qemu.sh
COPY setup_network.sh /usr/local/bin/setup_network.sh

RUN chmod +x /usr/local/bin/run-qemu.sh /usr/local/bin/setup_network.sh

VOLUME ["/shared"]
EXPOSE 6080

ENTRYPOINT ["/usr/local/bin/run-qemu.sh"]
