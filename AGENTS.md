# Workspace Agent Instructions

This repository uses the Codex agent to build a functional Lego Loco cluster. A development container is provided to ensure all dependencies are available. Begin every session by launching the dev container or installing the packages below so tests and development servers run correctly.

## Environment Setup
Use the `.devcontainer` configuration with VS Code or `devcontainer up` for a ready‑made environment based on `mcr.microsoft.com/devcontainers/base:ubuntu-22.04`. It includes Node.js 22, Docker‑in‑Docker and the Kubernetes tools `kubectl` v1.33.2, `kind` v0.23.0, `helm` v3.14.3 and `talosctl` v1.3.7.

If you cannot use the dev container, run the following commands in the workspace shell instead:

```bash
sudo apt-get update
sudo apt-get install -y nodejs npm qemu-system-x86 qemu-kvm wine gstreamer1.0-tools pulseaudio docker.io tcpdump
# kubectl is optional and may need manual installation if missing from apt
cd backend && npm install && cd ..
cd frontend && npm install && cd ..
```

The agent should execute these steps before running any other commands.

## Sequential Prompts for Future Work
The repository is incomplete. Use the following tasks in order to finish the project. Each task can be used as a Codex prompt:

1. **Backend Functionality** – extend `backend/server.js` with a WebSocket signaling server, serve config files, and proxy VNC/WebRTC traffic.
2. **Frontend Enhancements** – load instance data from `config/instances.json`, implement hotkeys from `config/hotkeys.json`, and create a `useWebRTC` hook with audio meters.
3. **Windows 98 Container Images** – provide Dockerfiles for QEMU/PCem/Wine that boot Windows 98 with Lego Loco installed, capture audio/video with PulseAudio and GStreamer, and join a shared TAP bridge LAN.
4. **Kubernetes Deployment** – write manifests or a Helm chart to launch nine emulator pods plus the backend, mount config as ConfigMaps, and expose each stream.
5. **Healthy Cluster Tests** – add scripts `k8s-tests/test-network.sh` and `k8s-tests/test-broadcast.sh` and integrate them into CI.
6. **Web Audio/Video Access** – ensure streaming pipelines allow browser access with mute, volume, and fullscreen controls.
7. **Optional VR Interface** – prototype an A-Frame or Three.js scene showing the 3×3 grid in VR and tie controller input to backend hotkeys.

Completing these tasks will yield a Windows 98 cluster that communicates over a virtual LAN and streams audio/video to the web interface.
