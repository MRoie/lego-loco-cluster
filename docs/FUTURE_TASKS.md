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

## In-Game LAN Networking (CRITICAL – currently broken)

> **Status**: Each QEMU container creates an isolated `loco-br` bridge at
> `192.168.10.1/24`. Guests **cannot see each other at Layer 2**. DirectPlay
> LAN discovery and Lego Loco multiplayer are **non-functional**. User-mode
> (NAT) fallback in `qemu-manager.sh` and Kind overlays makes this worse.

12. **Shared L2 Virtual Network Between QEMU Guests**
    - Replace per-container isolated `loco-br` bridges with a shared L2 segment
      so all Win98 guests reside on the same broadcast domain.
    - **Option A – QEMU socket networking**: Use `-netdev socket,listen=` on instance-0
      and `-netdev socket,connect=<instance-0>:PORT` on all others. Zero
      infrastructure changes; works in Docker Compose and Kubernetes alike.
    - **Option B – VXLAN overlay**: Create a VXLAN mesh between containers so
      every `loco-br` is bridged into a cluster-wide L2 segment. Requires an
      init-container or DaemonSet to set up VXLAN endpoints.
    - **Option C – Multus + macvlan (K8s only)**: Attach a secondary macvlan
      interface to each pod for direct L2 connectivity.
    - Update `entrypoint.sh` in all three QEMU container variants
      (`qemu/`, `qemu-softgpu/`, `qemu-bootable/`).
    - Add `NETWORK_MODE` Helm value: `socket | vxlan | macvlan | user` (default: `socket`).
    - Ensure `qemu-manager.sh` production `run` mode uses the shared network
      instead of user-mode NAT.

13. **DirectPlay & Game Port Configuration**
    - Forward TCP/UDP 2300 (Lego Loco) and 47624 (DirectPlay helper) between
      all QEMU guests on the shared L2 segment.
    - Configure Win98 guest TCP/IP stack with unique static IPs per instance
      (e.g., `192.168.10.10` through `192.168.10.18`) via QEMU DHCP or
      pre-baked registry hives in the snapshot.
    - Validate DirectPlay service advertisement and discovery across instances.
    - Add a `k8s-tests/test-directplay.sh` that verifies port 2300 reachability
      from every pod to every other pod.

14. **IPX/NetBIOS Support (Optional Legacy)**
    - If Lego Loco's DirectPlay provider uses IPX, configure `ipx_interface` or
      an IPX-over-UDP tunnel between guests.
    - Install NetBEUI/NetBIOS drivers in the Win98 snapshot if broadcast-based
      game discovery requires it.
    - Test with `tcpdump -i loco-br` inside containers to confirm broadcast
      frames propagate across the shared segment.

15. **Network Health & LAN Topology Dashboard**
    - Extend `health-monitor.sh` to report cross-container L2 reachability
      (ARP table, ping neighbours, DirectPlay port checks).
    - Surface LAN topology in the backend `/api/lan-status` endpoint.
    - Show a LAN connectivity heat-map on the frontend dashboard (who can
      see whom for multiplayer).

---

## Computer-Use Benchmark & In-Game Automation

> **Status**: `bench.py` is a stub (FPS/bitrate = 0). No scripts inject
> mouse/keyboard events into QEMU guests. No automated gameplay or LAN
> lobby verification exists.

16. **Real Benchmark Harness (replace bench.py stub)**
    - Collect actual metrics via QEMU QMP `query-display`, GStreamer bus
      messages, and container `docker stats`.
    - Measure: stream FPS, H.264 encode bitrate, end-to-end latency
      (capture → WebRTC decode), CPU/memory per instance.
    - Record results per replica count (1 / 3 / 9) to CSV and generate
      a Markdown performance report.
    - Integrate into CI as a nightly performance regression job.

17. **QMP-Based Computer-Use Agent**
    - Build a Node.js or Python service that connects to QEMU's QMP socket
      (`-qmp unix:/tmp/qmp.sock,server,nowait`) in each container.
    - Expose a REST/WebSocket API: `POST /input/{instanceId}` accepting
      `{ type: "mouse"|"key", x?, y?, button?, key?, action: "press"|"release" }`.
    - Use QMP `input-send-event` to inject `abs-pointer` (mouse) and
      `key` (keyboard) events directly into the guest.
    - Package as a sidecar or integrate into the emulator container.
    - This replaces the planned Go input-proxy (task 6) with a lighter
      QMP-native approach.

18. **Automated Lego Loco LAN Session Test**
    - Script that orchestrates a full multiplayer session:
      1. Wait for all instances to reach `ready` state via `/api/instances`.
      2. Use the QMP computer-use agent to navigate the Lego Loco main menu
         on instance-0 (host) and select "Start Network Game".
      3. On instances 1–N, navigate to "Join Network Game" and select the
         host's game session.
      4. Verify all players appear in the lobby by capturing VNC screenshots
         and running OCR or pixel-diff checks.
      5. Start the game and measure frame rate / input responsiveness for
         60 seconds of gameplay.
    - Requires the shared L2 network (task 12) to be functional.
    - Output a `BENCHMARK_LAN_SESSION.md` report with per-instance metrics.

19. **Input-to-Display Latency Benchmark**
    - Inject a known input (e.g., keystroke that triggers a visible UI change)
      via QMP, simultaneously start a timer.
    - Capture VNC/WebRTC frames and detect the expected visual change.
    - Measure the round-trip latency from input injection → pixel change
      arriving at the browser.
    - Target: < 150ms for smooth interactive feel.

20. **Streaming Pipeline Profiling**
    - Instrument every stage: QEMU framebuffer → Xvfb → GStreamer capture →
      H.264 encode → RTP packetize → UDP → WebRTC relay → browser decode →
      canvas paint.
    - Identify the bottleneck for each stage (capture latency, encode time,
      network jitter, decode time).
    - Output a pipeline flame-chart and per-stage timing breakdown.
    - Provide auto-tuning recommendations (bitrate, resolution, preset,
      queue depths).

---

## Smooth Ops & Production Hardening

21. **Zero-Downtime Rolling Updates**
    - Implement proper `maxUnavailable` / `maxSurge` in the StatefulSet
      update strategy so emulator pods cycle without dropping all streams.
    - Add pre-stop hooks to gracefully drain VNC/WebRTC connections before
      pod termination.
    - Test with `helm upgrade` during an active LAN game session.

22. **Startup Time Optimization**
    - Profile container boot: QEMU cold-start + Win98 boot + SoftGPU init +
      GStreamer pipeline negotiation.
    - Target: under 45 seconds from pod scheduled → game desktop visible.
    - Use QEMU snapshots (`-loadvm`) to skip Win98 boot and jump straight
      to the Lego Loco title screen.
    - Implement startup probe with 30-second `failureThreshold` window.

23. **Multi-Instance Stress Test**
    - Launch the full 3×3 grid (9 emulators) and run the LAN session
      benchmark (task 18) for 30 minutes continuously.
    - Monitor for memory leaks, CPU creep, GStreamer pipeline stalls,
      WebSocket disconnects, and OOM kills.
    - Record resource utilization time-series and flag any degradation > 10%
      from baseline.

24. **CI Performance Gate**
    - Add a GitHub Actions job that runs the benchmark harness (task 16) on
      every PR and compares against stored baselines.
    - Fail the check if stream FPS drops > 15%, latency increases > 20ms,
      or CPU per instance increases > 10%.
    - Store baseline CSV artefacts and trend charts in the repo wiki or as
      PR comments.
