# Loco LAN

Loco LAN runs multiple instances of Lego Loco inside emulated Windows 98 environments.
A web dashboard streams each emulator and provides keyboard, mouse and audio control.
The stack uses Docker and Kubernetes so you can spin up the whole cluster with a
single command.

## Features
- 3×3 grid of WebRTC streams
- Audio passthrough with meters
- Dockerized Windows 98 images
- Helm chart for Kubernetes
 - Simple dev container
 - Optional VR desktop viewer on port 3002

## Repository Layout
- `backend/` – signaling and API server
- `frontend/` – React dashboard
- `containers/` – emulator Dockerfiles
- `compose/` – Docker Compose configurations
- `helm/` – Helm chart
- `k8s/` – manifests and kind config
- `k8s-tests/` – cluster tests
- `scripts/` – helper utilities
- `tests/` – assorted test configs
- `docs/` – documentation
- `docs/REPOSITORY_SUMMARY.md` – overview of the project
- `docs/FUTURE_TASKS.md` – remaining high level goals

## Quick Setup
Install system packages and Node dependencies:

```bash
sudo apt-get update
sudo apt-get install -y nodejs npm qemu-system-x86 qemu-kvm wine gstreamer1.0-tools pulseaudio docker.io tcpdump
cd backend && npm install && cd ..
cd frontend && npm install && cd ..
```

Start the development stack with:

```bash
./scripts/dev-start.sh
```

## Loco Tools
Additional helper scripts live in the `scripts/` directory. Use
`scripts/decompress_loco_file.sh` to fetch an asset from any LAN URL and
decompress it with the bundled Java utility. Decoded files are copied to the
`net-shares/` directory so other pods can access them over the network.

Game assets are synchronized through a watcher. Each emulator pod mounts an NFS
share and `containers/qemu/watch_art_res.sh` automatically commits changes in
`<nfs>/<pod>/art/res` back to Git.

```bash
./scripts/decompress_loco_file.sh http://lan-host/file.dat
```

### VR Desktop Viewer

After the stack is running, a separate `vr-frontend` container serves the VR
dashboard on port `3002`. Open `http://localhost:3002` in a WebXR compatible
browser or headset to view all nine instances in VR.
See `docs/VR_STREAMING_PLAN.md` for the full blueprint.
### Scaling Instances

The helper script `scripts/deploy_single.sh` deploys the cluster via Helm. Set
the `REPLICAS` environment variable to run `1`, `3` or `9` emulator pods:

```bash
REPLICAS=1 ./scripts/deploy_single.sh   # single instance
REPLICAS=3 ./scripts/deploy_single.sh   # three instances
REPLICAS=9 ./scripts/deploy_single.sh   # full grid
```
A future goal is to minimize resource usage by focusing on a configurable list
of active containers. See `docs/ACTIVE_STATE_PLAN.md` for details. The helper
script `scripts/set_active.sh` updates the active instance list and notifies all
connected clients. For hardware control an EV3 brick can run
`scripts/ev3_focus_ws.py` to cycle and select the focused instance using the
arrow and center buttons.
When run locally the script also uses Docker to throttle unfocused emulator
containers so the active ones receive the most CPU time.
For Kubernetes deployments, CPU requests and limits can be configured via the
`emulator.resources` section in `helm/loco-chart/values.yaml` and adjusted
dynamically with `scripts/set_active.sh`.
The VR scene now includes spatial audio so each emulator can be heard in
3D space. Instances in the active list play at full volume while others are
dimmed, with a per-instance volume slider available in VR.

Audio behaviour is controlled by `config/camu.json`. Spatial audio and
translation quality settings can be tweaked there to ensure the CAMU pipeline
produces high quality output across all stacks.
