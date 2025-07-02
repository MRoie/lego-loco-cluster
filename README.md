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
 - Optional VR desktop viewer on port 3002

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

### VR Desktop Viewer

After the stack is running, a separate `vr-frontend` container serves the VR
dashboard on port `3002`. Open `http://localhost:3002` in a WebXR compatible
browser or headset to view all nine instances in VR.

### Scaling Instances

The helper script `scripts/deploy_single.sh` deploys the cluster via Helm. Set
the `REPLICAS` environment variable to run `1`, `3` or `9` emulator pods:

```bash
REPLICAS=1 ./scripts/deploy_single.sh   # single instance
REPLICAS=3 ./scripts/deploy_single.sh   # three instances
REPLICAS=9 ./scripts/deploy_single.sh   # full grid
```

