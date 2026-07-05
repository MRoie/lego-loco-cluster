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

### ⚠️ CRITICAL: Use Rigorous Deployment Scripts

**Common Problem**: Simply running `docker build` + `helm upgrade` does NOT guarantee container replacement. Kubernetes may not pull the new image, especially when reusing tags like `latest`.

**Solution**: ALWAYS use the rigorous deployment script when modifying Dockerfiles or source code:

```bash
# Rebuild entire stack (backend, frontend, VR) with unique timestamped tags
./scripts/deploy_backend_rigorous.sh [optional-tag]
```

**What this script does**:
1. Builds ALL images (backend, frontend, VR) with unique timestamped tags
2. Loads all images into Minikube/Kind
3. Verifies all images are present in cluster
4. Forces Helm upgrade with new tags for all services
5. Waits for all deployment rollouts to complete
6. Shows deployment summary and pod status

**Why this matters**: Without this process, your code changes may not be reflected in the running pods, leading to confusion during debugging and verification.

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

## In-Game LAN Networking (CRITICAL)
> **Current state**: Each QEMU container creates an isolated `loco-br` bridge at `192.168.10.1/24`. Guests cannot see each other at L2. DirectPlay LAN discovery and Lego Loco multiplayer are **non-functional**. No IPX, NetBIOS, or QEMU socket networking is configured anywhere.

16. **Shared L2 Virtual Network Between QEMU Guests** – Replace isolated per-container bridges with a shared L2 segment. Preferred approach: QEMU socket networking (`-netdev socket,listen=` / `-netdev socket,connect=`). Alternative: VXLAN overlay or Multus macvlan. Update all three entrypoint.sh variants. Add `NETWORK_MODE` Helm value (`socket | vxlan | macvlan | user`). Ensure `qemu-manager.sh` production mode uses shared networking.

17. **DirectPlay & Game Port Configuration** – Forward TCP/UDP 2300 (Lego Loco) and 47624 (DirectPlay) between guests on shared L2 segment. Configure unique static IPs per instance via DHCP or pre-baked registry hives. Add `k8s-tests/test-directplay.sh` for port 2300 cross-pod reachability.

18. **IPX/NetBIOS Support (Optional Legacy)** – Configure IPX-over-UDP tunnel or NetBEUI drivers in Win98 snapshot if DirectPlay requires broadcast-based discovery. Validate with tcpdump on bridge interfaces.

19. **LAN Topology Dashboard** – Extend health-monitor.sh to report cross-container L2 reachability (ARP table, neighbour ping, DirectPlay port checks). Add `/api/lan-status` backend endpoint. Show LAN connectivity heat-map on frontend.

## Computer-Use Benchmarks & In-Game Automation
> **Current state**: `bench.py` is a stub returning hardcoded zero metrics. No scripts inject mouse/keyboard into QEMU guests. No automated gameplay or LAN lobby verification exists.

20. **Real Benchmark Harness** – Replace bench.py stub with actual metric collection via QMP `query-display`, GStreamer bus messages, and `docker stats`. Measure stream FPS, H.264 bitrate, end-to-end latency, CPU/memory per instance across replica counts (1/3/9). Generate CSV + Markdown performance report. Integrate into CI as nightly regression job.

21. **QMP Computer-Use Agent** – Build a service connecting to QEMU's QMP socket in each container. Expose REST/WebSocket API for mouse/keyboard injection via `input-send-event`. Supersedes the Go input-proxy (task 6) with a lighter QMP-native approach. Package as sidecar or integrate into emulator container.

22. **Automated LAN Session Test** – Orchestrate a full Lego Loco multiplayer session: wait for all instances ready, use QMP agent to navigate menus (host creates game, clients join), verify lobby via VNC screenshot + OCR/pixel-diff, start game and measure FPS/input responsiveness for 60 seconds. Requires shared L2 network (task 16). Output `BENCHMARK_LAN_SESSION.md`.

23. **Input-to-Display Latency Benchmark** – Inject known input via QMP, capture VNC/WebRTC frames to detect visual change, measure round-trip latency. Target < 150ms for smooth interactive feel.

24. **Streaming Pipeline Profiling** – Instrument every stage from QEMU framebuffer → Xvfb → GStreamer capture → H.264 encode → RTP → UDP → WebRTC relay → browser decode → canvas paint. Identify per-stage bottlenecks, output flame-chart and timing breakdown, provide auto-tuning recommendations.

## Smooth Ops & Production Hardening

25. **Zero-Downtime Rolling Updates** – Implement proper `maxUnavailable`/`maxSurge` in StatefulSet update strategy. Add pre-stop hooks for graceful VNC/WebRTC drain. Test with `helm upgrade` during active LAN sessions.

26. **Startup Time Optimization** – Profile full boot sequence (QEMU cold-start → Win98 boot → SoftGPU → GStreamer). Target < 45s to game desktop. Use QEMU `-loadvm` snapshots to skip Win98 boot. Implement startup probe with 30s failure threshold.

27. **Multi-Instance Stress Test (3×3 Grid)** – Run all 9 emulators with LAN session benchmark for 30 minutes. Monitor for memory leaks, CPU creep, GStreamer stalls, WebSocket disconnects, OOM kills. Record resource utilization time-series and flag > 10% degradation.

28. **CI Performance Gate** – GitHub Actions job running benchmark harness on every PR against stored baselines. Fail if stream FPS drops > 15%, latency increases > 20ms, or CPU per instance increases > 10%. Store baseline artefacts and trend charts.
