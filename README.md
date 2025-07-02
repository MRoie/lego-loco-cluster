# Loco LAN

Loco LAN runs multiple instances of Lego Loco inside emulated Windows 98 environments.
A web dashboard streams each emulator and provides keyboard, mouse and audio control.
The stack uses Docker and Kubernetes so you can spin up the whole cluster with a
single command.

## Features
- 3×3 grid of WebRTC streams
- Audio passthrough with meters
- Dockerized Windows 98 images
- Helm chart for Kubernetes
- Simple dev container

## Repository Layout
- `backend/` – signaling and API server
- `frontend/` – React dashboard
- `containers/` – emulator Dockerfiles
- `compose/` – Docker Compose configurations
- `helm/` – Helm chart
- `k8s/` – manifests and kind config
- `k8s-tests/` – cluster tests
- `scripts/` – helper utilities
- `tests/` – assorted test configs
- `docs/` – documentation
- `docs/REPOSITORY_SUMMARY.md` – overview of the project
- `docs/FUTURE_TASKS.md` – remaining high level goals

## Quick Setup
Install system packages and Node dependencies:

```bash
sudo apt-get update
sudo apt-get install -y nodejs npm qemu-system-x86 qemu-kvm wine gstreamer1.0-tools pulseaudio docker.io tcpdump
cd backend && npm install && cd ..
cd frontend && npm install && cd ..
```

Start the development stack with:

```bash
./scripts/dev-start.sh
```

Measure VR streaming performance with:

```bash
make vr-benchmark STREAM_URL=http://localhost:6090/stream
```

Compare performance at 1, 3 and 9 emulators:

```bash
./scripts/benchmark_cluster.sh
```
