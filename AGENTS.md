# Workspace Agent Instructions

> **Note for Agents**: Please also refer to the **[Contributors Guide](docs/CONTRIBUTING.md)** and **[Architecture Overview](docs/ARCHITECTURE.md)** for detailed system design and contribution workflows.

This repository uses the Codex agent to build a functional Lego Loco cluster. A# Development Guidelines

## 🚀 Deployment & Verification Workflow (CRITICAL)
**There is NO HOT-RELOAD available in this environment.** Any code or Dockerfile change requires the following strict process:

1.  **Rebuild**: Build the image with a **NEW** unique tag (e.g., timestamp or version). Do NOT reuse `latest`.
    ```bash
    docker build -f <Dockerfile> -t <image>:<new-tag> .
    ```
2.  **Load**: Load the image into the cluster (Minikube/Kind).
    ```bash
    minikube image load <image>:<new-tag>
    ```
3.  **Verify Image**: Confirm the image is present in the cluster.
    ```bash
    minikube image ls | grep <image>:<new-tag>
    ```
4.  **Upgrade**: Upgrade the Helm chart to use the new tag.
    ```bash
    helm upgrade --install <release> ./helm/<chart> -n <ns> --set <service>.tag=<new-tag>
    ```
5.  **Verify Deployment**: Wait for pods to be ready and healthy.
    ```bash
    kubectl rollout status deployment/<deployment-name> -n <ns>
    ```
6.  **Test**: Rerun verification tests only AFTER the deployment is confirmed ready.

---
r is provided to ensure all dependencies are available. Begin every session by launching the dev container or installing the packages below so tests and development servers run correctly.

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

1. ✅ **SoftGPU Snapshot Integration** – **COMPLETED**: Implemented via `scripts/create_win98_image.sh` and `snapshot_builder.py`.
2. ✅ **Persistent Storage** – **COMPLETED**: Helm chart supports `storage` configuration (HostPath, NFS, Hybrid).
3. ✅ **Cluster Bootstrap Scripts** – **COMPLETED**: `bootstrap-cluster.sh` and `start_live_cluster.sh` implemented.
4. ✅ **Extended Cluster Tests** – **COMPLETED**: `k8s-tests/` contains network, TCP, and broadcast tests.
5. ✅ **Frontend, Streaming and VR Polishing** – **COMPLETED**: Audio output selection, reconnect logic, and VR scene finalized.

## Video/Audio Quality Monitoring and Testing (New)
The backend now includes comprehensive stream quality monitoring with real-time probing and metrics collection. Additional quality monitoring features to implement:

6. **Advanced WebRTC Statistics Integration** – extend the `useWebRTC` hook to collect detailed RTCStats including bandwidth utilization, codec information, network conditions, and adaptive bitrate suggestions. Integrate these client-side metrics with the backend monitoring service.

7. **Quality-Adaptive Streaming** – implement dynamic quality adjustment based on detected network conditions, automatically reducing frame rates, resolution, or switching codecs when packet loss or latency thresholds are exceeded. Add user controls for quality preferences.

8. **Real-time Quality Dashboard** – create a comprehensive monitoring dashboard showing live quality metrics, historical trends, alert notifications for quality degradation, and comparative analysis across all instances. Include quality heat maps and performance charts.

9. ✅ **QEMU Audio/Video Health Probing** – **COMPLETED**: Extended monitoring service to probe actual QEMU audio/video subsystem health beyond network connectivity. Implemented deeper inspection of video frame generation rates, audio buffer states, GPU rendering performance, and network interface health through container health endpoints.

10. **Stream Quality Testing Suite** – create comprehensive automated tests for video/audio quality scenarios including simulated network degradation, bandwidth constraints, codec switching, and multi-instance load testing. Integrate with CI/CD pipeline.

11. ✅ **Quality Failure Detection and Recovery** – **COMPLETED**: Implemented intelligent failure detection that distinguishes between network issues, QEMU problems, and client-side issues. Added automatic recovery mechanisms including stream restart, quality fallback, and instance failover with configurable attempt limits.

12. **Performance Profiling and Optimization** – add detailed performance profiling for the entire streaming pipeline, identify bottlenecks in video encoding, network transmission, and client-side decoding. Implement optimization recommendations and automatic tuning.

Completing these tasks will yield a robust Windows 98 cluster with automated deployment, reliable streaming and a polished VR experience.


## Instance Management Revolution (New)
13. ✅ **Kubernetes Auto-Discovery Integration** – **COMPLETED**: Eliminated the need for manual instances.json maintenance through comprehensive Kubernetes service discovery. Backend now automatically discovers emulator instances from StatefulSet pods with real-time updates, proper RBAC integration, and intelligent fallback to static configuration.

## Enhanced Testing & CI (New)
14. ✅ **Comprehensive Monitoring Integration Tests** – **COMPLETED**: Added comprehensive test suite validating container health monitoring, API endpoints, auto-discovery, and recovery mechanisms. Integrated monitoring tests into CI pipeline with proper cluster setup and validation.

15. ✅ **Container Health Instrumentation** – **COMPLETED**: Enhanced QEMU containers with detailed health monitoring scripts exposing metrics via HTTP endpoints. Integrated health monitoring into Helm charts with proper port exposure and configuration.
