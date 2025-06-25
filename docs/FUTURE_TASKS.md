# Future Tasks

The following steps will complete the Loco LAN cluster. Each item can be used as
a future Codex prompt.

1. **Windows 98 Disk Image**
   - Follow `docs/win98_image.md` to create a disk image with Lego Loco installed.
   - Provide scripts (`create_win98_image.sh`/`.ps1`) that convert and package the image for container use.
   - Update emulator entrypoints to read the image path from an environment variable.

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

5. **Frontend and Streaming Polishing**
   - Allow users to select audio output devices per instance.
   - Add reconnect logic to `useWebRTC` for dropped connections and show loading indicators while streams establish.

6. **Optional VR Interface**
   - Prototype a simple A-Frame or Three.js scene rendering the 3×3 grid in VR.
   - Map controller input to existing backend hotkey actions.

Completing these tasks will produce a robust Windows 98 cluster with automated deployment, reliable streaming and an optional VR mode.


