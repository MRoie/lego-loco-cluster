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

## Loco Tools
Additional helper scripts live in the `scripts/` directory. Use `scripts/decompress_loco_file.sh` to fetch an asset from any LAN URL and decompress it with the bundled Java utility.

Game assets are synchronized through a new watcher. Each emulator pod mounts an
NFS share and `containers/qemu/watch_art_res.sh` automatically commits changes in
`<nfs>/<pod>/art/res` back to Git.

```bash
./scripts/decompress_loco_file.sh http://lan-host/file.dat decompressed.dat
```
