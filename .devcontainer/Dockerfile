FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04

# Install core packages for Loco LAN development
ARG KUBECTL_VERSION="v1.33.2"
ARG KIND_VERSION="v0.23.0"
ARG HELM_VERSION="v3.14.3"
ARG TALOSCTL_VERSION="v1.3.7"

RUN apt-get update \
    && apt-get install -y \
        nodejs npm qemu-system-x86 qemu-kvm \
        wine gstreamer1.0-tools pulseaudio docker.io tcpdump \
        curl tar \
    && curl -Lo /usr/local/bin/kubectl https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl \
    && chmod +x /usr/local/bin/kubectl \
    && curl -Lo /usr/local/bin/kind https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64 \
    && chmod +x /usr/local/bin/kind \
    && curl -Lo helm.tar.gz https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz \
    && tar -xzvf helm.tar.gz linux-amd64/helm --strip-components=1 \
    && mv helm /usr/local/bin/helm \
    && rm -rf helm.tar.gz linux-amd64 \
    && curl -L https://github.com/siderolabs/talos/releases/${TALOSCTL_VERSION}/download/talosctl-linux-amd64 -o /usr/local/bin/talosctl \
    && chmod +x /usr/local/bin/talosctl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Default to a long running sleep so the container stays alive
CMD ["sleep", "infinity"]
