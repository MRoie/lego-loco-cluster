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

## Inspecting the Repository for Remote Environments
Look for a `.devcontainer` directory to confirm the container configuration. If
the file contains a line starting with `Remote dev server:` or the
`REMOTE_DEV_SERVER` environment variable is set, connect to that URL with SSH or
HTTPS authentication instead of starting a new container. If no remote endpoint
is found, build the dev container locally.

## Persistent Remote Environment (Optional)
If you prefer to keep the dev setup running at all times, host the
`.devcontainer` image on a separate machine and expose a VS Code server
(for example `code-server` or `openvscode-server`) over HTTPS or an SSH
tunnel. This provides a persistent workspace so new sessions can attach
without rebuilding the container.

1. Start the container on the remote host with `docker run` and mount the
   repository:

   ```bash
   docker run -d --name loco-dev --privileged \
     --device=/dev/kvm -p 8443:8443 \
     -v /path/to/lego-loco-cluster:/workspaces/lego-loco-cluster \
     mcr.microsoft.com/devcontainers/base:ubuntu-22.04
   ```

2. Inside the container, install a VS Code server and launch it:

   ```bash
   curl -fsSL https://code-server.dev/install.sh | sh
   code-server --bind-addr 0.0.0.0:8443
   ```

3. Protect the endpoint using HTTPS and authentication (for example with
   Nginx or Caddy). Record the URL in this file so the agent and
   collaborators can connect directly:

   ```
   Remote dev server: https://yourdomain.example.com
   ```

Ensure the remote host has the packages listed in **Environment Setup** so
tests and development servers run correctly.

## Joining an Online Codespace
If someone has a GitHub Codespace running for this project, the address may be
provided as a `Codespace URL:` line in this file or via the `CODESPACE_URL`
environment variable. Open that HTTPS link in your browser or run
`code https://yourspace.github.dev` to attach directly without launching a local
container.

```text
Codespace URL: https://yourname-lego-loco-abc123.github.dev
```

Connecting to the codespace gives you a ready-to-use workspace with all
dependencies installed.

## Sequential Prompts for Future Work
The core development environment is functional, but several features remain. Use the following tasks in order to finish the project. Each item can be used as a Codex prompt:

1. **SoftGPU Snapshot Integration** – download the latest snapshot containing SoftGPU and Lego Loco from `ghcr.io/mroie/qemu-snapshots` and ensure emulator containers boot from it. Provide fallback scripts to build the snapshot using `docs/win98_image.md`.
2. **Persistent Storage** – update the Helm chart so emulator pods mount the image from a PVC and allow a read‑only mode.
3. **Cluster Bootstrap Scripts** – add helpers to upload the image into the cluster, patch the Helm release and regenerate `config/instances.json`.
4. **Extended Cluster Tests** – expand `k8s-tests/test-network.sh`, add `test-boot.sh`, and run the full suite in CI.
5. **Frontend, Streaming and VR Polishing** – implement audio device selection, reconnect logic and loading indicators in `useWebRTC`, and deliver a production-ready VR mode with minimal latency.

Completing these tasks will yield a robust Windows 98 cluster with automated deployment, reliable streaming and a polished VR experience.

