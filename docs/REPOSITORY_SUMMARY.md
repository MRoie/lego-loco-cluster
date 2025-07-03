# Repository Summary

Loco LAN emulates multiple Windows 98 environments running Lego Loco. Each
instance streams audio and video to a React dashboard. Development tooling is
based on Docker and Kubernetes so the whole cluster can be started with a single
command.

## Key Components
- **backend/** – Express server providing WebSocket proxies and configuration APIs
- **frontend/** – React dashboard displaying the 3×3 grid of streams
- **containers/** – Dockerfiles for QEMU-based emulator images
- **compose/** – Docker Compose files for local development and testing
- **helm/** – Helm chart for deploying the cluster
- **scripts/** – Helper utilities to build images, start services and manage tests

A VS Code dev container is provided under `.devcontainer` with Node.js 22,
Docker‑in‑Docker and the Kubernetes CLIs. Run `devcontainer up` to get a ready
environment. Alternatively install the packages listed in `AGENTS.md`.

Prebuilt snapshots containing SoftGPU and Lego Loco are available from
`ghcr.io/mroie/qemu-snapshots` to speed up emulator startup.

## Current Status
The development environment supports live reloading for both backend and
frontend. Configuration files in `config/` are watched automatically. The Docker
Compose setup runs a minimal stack or the full set of nine emulators. CI
workflows build the images and run basic network tests.

A VR mode is also available. The `vr-frontend` container exposes the dashboard
in WebXR so all instances can be viewed in a headset.

For a detailed outline of upcoming VR features, see `docs/VR_STREAMING_PLAN.md`.



Future work includes implementing an active container focus system so only the
selected emulator runs at full speed. See `docs/ACTIVE_STATE_PLAN.md` for the
roadmap and associated tasks. Use `scripts/set_active.sh` to update the list of
focused instances during development. The EV3 helper `scripts/ev3_focus_ws.py`
can change focus using the brick's buttons. When switching focus locally the
script throttles other containers using Docker CPU quotas so the active
emulators get full performance.
Helm deployments can set CPU requests and limits via `emulator.resources` in
`values.yaml` and Docker Compose includes example quotas for local testing.
Spatial audio has been added to the VR experience so that each emulator's sound
originates from its screen position. Instances in the active list are loudest
while the others play softly for ambient feedback.
Audio parameters are stored in `config/camu.json` so CAMU-based pipelines can
produce high fidelity spatial output.
