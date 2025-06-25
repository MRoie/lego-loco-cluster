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


