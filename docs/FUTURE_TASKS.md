# Future Tasks

The following steps will complete the Loco LAN cluster. Each item can be used as
a future Codex prompt.

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

8. **Codec Benchmark Harness** (✅ DONE)
   - `benchmark/bench.py` implemented.

9. **WebXR End-to-End Tests** (✅ DONE)
   - `playwright-vnc-web-test.js` implemented.

10. **Observability Stack** (✅ DONE)
    - Custom `streamQualityMonitor.js` implemented.
    - `docs/MONITORING.md` created.

11. **Active Container Focus** (✅ DONE)
    - Full system implemented. See `docs/ACTIVE_STATE_PLAN.md`.
