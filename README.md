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

A future goal is to minimize resource usage by focusing on a single active
container at a time. See `docs/ACTIVE_STATE_PLAN.md` for details. The helper
script `scripts/set_active.sh` updates the active instance and notifies all
connected clients. For hardware control an EV3 brick can run
`scripts/ev3_focus_ws.py` to cycle and select the focused instance using the
arrow and center buttons.
When run locally the script also uses Docker to throttle unfocused emulator
containers so the active one receives the most CPU time.
The VR scene now includes spatial audio so each emulator can be heard in
3D space. The focused instance plays at full volume while others are
dimmed, with a per-instance volume slider available in VR.
