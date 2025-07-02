# Workspace Agent Instructions

This repository uses the Codex agent to build a functional Lego Loco cluster. A development container is provided to ensure all dependencies are available. Begin every session by launching the dev container or installing the packages below so tests and development servers run correctly.

## Environment Setup
Use the `.devcontainer` configuration with VS Code or `devcontainer up` for a ready‑made environment based on `mcr.microsoft.com/devcontainers/base:ubuntu-22.04`. It includes Node.js 22, Docker‑in‑Docker and the Kubernetes tools `kubectl` v1.33.2, `kind` v0.23.0, `helm` v3.14.3 and `talosctl` v1.3.7.
### GitHub Codespaces (Recommended)
For the fastest setup with AI coding assistance, use GitHub Codespaces:

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/MRoie/lego-loco-cluster)

The Codespace comes pre-configured with:
- GitHub Copilot for AI-assisted coding
- Optimized VS Code settings for development
- All dependencies pre-installed
- Debug configurations ready to use

### Local Development

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
The core development environment is functional, but several features remain. Use the following tasks in order to finish the project. Each item can be used as a Codex prompt:

1. **SoftGPU Snapshot Integration** – download the latest snapshot containing SoftGPU and Lego Loco from `ghcr.io/mroie/qemu-snapshots` and ensure emulator containers boot from it. Provide fallback scripts to build the snapshot using `docs/win98_image.md`.
2. **Persistent Storage** – update the Helm chart so emulator pods mount the image from a PVC and allow a read‑only mode.
3. **Cluster Bootstrap Scripts** – add helpers to upload the image into the cluster, patch the Helm release and regenerate `config/instances.json`.
4. **Extended Cluster Tests** – expand `k8s-tests/test-network.sh`, add `test-boot.sh`, and run the full suite in CI.
5. **Frontend, Streaming and VR Polishing** – implement audio device selection, reconnect logic and loading indicators in `useWebRTC`, and deliver a production-ready VR mode with minimal latency.

Completing these tasks will yield a robust Windows 98 cluster with automated deployment, reliable streaming and a polished VR experience.

