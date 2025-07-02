# Future Tasks

The following steps will complete the Loco LAN cluster. Each item can be used as
a future Codex prompt.

1. **SoftGPU Snapshot Integration**
   - Use the latest snapshot files with SoftGPU and Lego Loco from `ghcr.io/mroie/qemu-snapshots`.
   - Provide fallback scripts (`create_win98_image.sh`/`.ps1`) so the snapshot can be rebuilt if needed.
   - Ensure emulator entrypoints read the image path from an environment variable.

2. **Persistent Storage**
   - Modify the Helm chart so emulator pods mount the disk image via a PersistentVolumeClaim.
   - Add a `diskReadOnly` toggle in `values.yaml` to allow sharing a base image.

3. **Cluster Bootstrap Scripts**
   - Create helpers to upload the disk image into the cluster and patch the Helm release with the correct PVC.
   - Extend `scripts/start_live_cluster.sh` to call these helpers and regenerate `config/instances.json`.

4. **Extended Cluster Tests**
   - Expand `k8s-tests/test-network.sh` with ARP table checks and IPv6 connectivity.
   - Add `k8s-tests/test-boot.sh` to verify each emulator exposes VNC and reaches the Windows desktop.
   - Ensure all tests run in CI and block merges on failure.

5. **Frontend, Streaming and VR Polishing**
   - Allow users to select audio output devices per instance.
   - Add reconnect logic to `useWebRTC` for dropped connections and show loading indicators while streams establish.
   - Finalize a production-ready VR scene with minimal latency and controller input mapped to backend hotkeys.
   - Deploy the `vr-frontend` container so the dashboard can be viewed in WebXR.

6. **Input Proxy Service**
   - Implement a Go WebSocket service that forwards JSON mouse and keyboard events to QEMU using QMP.
   - Package the service as `cmd/input-proxy` and run it as a sidecar with each emulator.

7. **Sunshine and Parsec Variants**
   - Create optional container builds with Sunshine and Parsec for traditional desktop streaming.
   - Document how to connect using Moonlight and the Parsec client.

8. **Codec Benchmark Harness**
   - Write `bench.py` to compare x264, VP8 and MJPEG at multiple frame rates.
   - Store results in `results.csv` and plot a chart for the documentation.

9. **WebXR End-to-End Tests**
   - Use Playwright to launch the VR dashboard headlessly and verify all streams render above 28 FPS.
   - Integrate the test with GitHub Actions so failures block merges.

10. **Observability Stack**
    - Deploy Prometheus and Grafana dashboards showing encode FPS and WebRTC latency.
    - Add an Alertmanager rule when any stream drops below 20 FPS.

Completing these tasks will produce a robust Windows 98 cluster with automated deployment, reliable streaming and a polished VR experience.


