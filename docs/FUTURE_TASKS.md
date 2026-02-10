# Future Tasks

The following steps will complete the Loco LAN cluster. Each item can be used as
a future Codex prompt.

## Completed Foundation

1. **SoftGPU Snapshot Integration** (✅ DONE)
   - Implemented via `scripts/create_win98_image.sh` and `snapshot_builder.py`.
   - Helm chart supports `usePrebuiltSnapshot`.

2. **Persistent Storage** (✅ DONE)
   - Helm chart supports `storage` configuration (HostPath, NFS, Hybrid).
   - `deploy-storage-options.sh` helper created.

3. **Cluster Bootstrap Scripts** (✅ DONE)
   - `bootstrap-cluster.sh` and `start_live_cluster.sh` implemented.

4. **Extended Cluster Tests** (✅ DONE)
   - `k8s-tests/` contains network, TCP, and broadcast tests.
   - `test_monitoring_integration.sh` covers full stack validation.

5. **Frontend, Streaming and VR Polishing** (✅ DONE)
   - Audio output selection implemented.
   - Reconnect logic added to `useWebRTC`.
   - VR Scene finalized with spatial audio.
   - `vr-frontend` container deployable.

6. **Input Proxy Service**
   - Implement a Go WebSocket service that forwards JSON mouse and keyboard events to QEMU using QMP.
   - Package the service as `cmd/input-proxy` and run it as a sidecar with each emulator.

7. **Sunshine and Parsec Variants**
   - Create optional container builds with Sunshine and Parsec for traditional desktop streaming.
   - Document how to connect using Moonlight and the Parsec client.

8. **Codec Benchmark Harness** (✅ DONE – stub only, see task 16 for real implementation)
   - `benchmark/bench.py` scaffolded. FPS/bitrate still hardcoded to 0.

9. **WebXR End-to-End Tests** (✅ DONE)
   - `playwright-vnc-web-test.js` implemented.

10. **Observability Stack** (✅ DONE)
    - Custom `streamQualityMonitor.js` implemented.
    - `docs/MONITORING.md` created.

11. **Active Container Focus** (✅ DONE)
    - Full system implemented. See `docs/ACTIVE_STATE_PLAN.md`.

---

## In-Game LAN Networking (CRITICAL)

> **Status**: ✅ Shared L2 networking implemented via QEMU socket mode.
> Entrypoints updated, Helm/Compose configured with `NETWORK_MODE=socket`.

12. **Shared L2 Virtual Network Between QEMU Guests** (✅ DONE)
    - Created `containers/qemu-softgpu/setup-lan-network.sh` supporting
      `NETWORK_MODE` values: `socket | vxlan | macvlan | user | bridge`.
    - QEMU socket networking: instance-0 listens (`-netdev socket,listen=:4444`),
      others connect (`-netdev socket,connect=master:4444`).
    - Updated `entrypoint.sh` in `qemu-softgpu/` and `qemu/` to source
      `setup-lan-network.sh` when `NETWORK_MODE != bridge`.
    - Added `NETWORK_MODE`, `SOCKET_PORT`, `SOCKET_MASTER_HOST`, `INSTANCE_ID`
      to Helm values and all 9 Docker Compose emulators.
    - StatefulSet template computes `SOCKET_MASTER_HOST` from headless service DNS.

13. **DirectPlay & Game Port Configuration** (✅ DONE)
    - Created `k8s-tests/test-directplay.sh` verifying TCP/UDP 2300 and 47624
      reachability between all emulator pods.
    - Docker Compose exposes port 4444 on emulator-0 for socket networking.

14. **IPX/NetBIOS Support (Optional Legacy)**
    - If Lego Loco's DirectPlay provider uses IPX, configure `ipx_interface` or
      an IPX-over-UDP tunnel between guests.
    - Install NetBEUI/NetBIOS drivers in the Win98 snapshot if broadcast-based
      game discovery requires it.
    - Test with `tcpdump -i loco-br` inside containers to confirm broadcast
      frames propagate across the shared segment.

15. **Network Health & LAN Topology Dashboard** (✅ DONE)
    - Added `/api/lan-status` endpoint to backend `server.js` — probes each
      instance's health for cross-container L2 reachability, ARP, DirectPlay ports.
    - Returns per-instance status, connectivity matrix, and overall LAN health.

---

## Computer-Use Benchmark & In-Game Automation

> **Status**: ✅ Real benchmark harness, QMP agent, LAN session test, latency
> benchmark, and pipeline profiler all implemented.

16. **Real Benchmark Harness** (✅ DONE)
    - Replaced stub `bench.py` with ~250-line real implementation.
    - Probes container `:8080/health` endpoints and `docker stats`/`kubectl top`.
    - Measures FPS, CPU%, memory, latency per instance across replica counts.
    - Outputs CSV + Markdown report with pass/fail criteria.
    - Integrated into CI as `performance-gate` job.

17. **QMP-Based Computer-Use Agent** (✅ DONE)
    - Created `tools/qmp-agent/qmp_agent.py` (~320 lines).
    - Connects to QMP Unix sockets per instance, injects `input-send-event`.
    - REST API: `POST /input/{instance_id}` for key/mouse events.
    - KEY_SCANCODES mapping for full keyboard coverage.
    - QMP socket configured in QEMU via `-qmp unix:/tmp/qmp-{INSTANCE_ID}.sock`.

18. **Automated Lego Loco LAN Session Test** (✅ DONE)
    - Created `benchmark/lan_session_test.py` (~260 lines).
    - Orchestrates full multiplayer: wait for ready → host creates game →
      clients join → 60s gameplay with FPS/CPU metrics → report.
    - Outputs `BENCHMARK_LAN_SESSION.md`.

19. **Input-to-Display Latency Benchmark** (✅ DONE)
    - Created `benchmark/input_latency_bench.py`.
    - Injects keys via QMP, measures round-trip to health response.
    - Runs configurable trials, computes mean/median/P95/stdev.
    - Generates `LATENCY_REPORT.md` with pass/fail vs 150ms target.

20. **Streaming Pipeline Profiling** (✅ DONE)
    - Created `benchmark/pipeline_profiler.py`.
    - Instruments: QEMU framebuffer → Xvfb → GStreamer → H.264 → RTP → UDP.
    - Per-process CPU breakdown, bottleneck identification.
    - Generates `PIPELINE_PROFILE.md` with auto-tuning recommendations.

---

## Smooth Ops & Production Hardening

> **Status**: ✅ Rolling updates, startup optimization, stress test, and CI
> performance gate all implemented.

21. **Zero-Downtime Rolling Updates** (✅ DONE)
    - Added `updateStrategy.rollingUpdate.maxUnavailable: 1` to StatefulSet.
    - Added `lifecycle.preStop` hook to gracefully drain GStreamer/VNC before
      pod termination (5s drain window).

22. **Startup Time Optimization** (✅ DONE)
    - Added `LOADVM_TAG` environment variable support in entrypoint.sh.
    - When set, QEMU uses `-loadvm $LOADVM_TAG` to skip Win98 boot and
      jump directly to saved state (target < 45s to game desktop).
    - QMP socket enabled for all instances for runtime control.

23. **Multi-Instance Stress Test** (✅ DONE)
    - Created `scripts/stress-test-9grid.sh` for 3×3 grid benchmarking.
    - Scales to 9 replicas, takes baseline + final measurements.
    - Monitors CPU/mem/FPS time-series at configurable intervals.
    - Detects OOM kills, generates degradation analysis report.

24. **CI Performance Gate** (✅ DONE)
    - Added `performance-gate` job to `.github/workflows/ci.yml`.
    - Creates cluster, runs `bench.py` with thresholds, checks for FAIL.
    - Uploads benchmark artifacts with 30-day retention.
    - Fails PR if performance degrades beyond limits.
