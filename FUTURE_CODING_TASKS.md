# Future Codex Agent Tasks for Loco LAN

This document lists the outstanding work required to make the repository fully functional in a new environment. Each numbered section can be treated as a standalone prompt for a future Codex agent. Follow them in order.

## 1. Environment Setup
- Install required system packages as described in `AGENTS.md`.
- Run `npm install` in both `backend/` and `frontend/`.
- Ensure Docker and Kubernetes (k3s) are available on the target machine.

## 2. Backend Functionality
- Expand `backend/server.js` to include a WebSocket signaling server.
- Implement routes to serve configuration from `config/`.
- Add logic to proxy VNC/WebRTC connections to the emulated machines.

## 3. Frontend Enhancements
- Replace hard-coded instance URLs in `frontend/src/App.jsx` with data loaded from `config/instances.json` via the backend.
- Implement hotkeys described in `config/hotkeys.json`.
- Add a `useWebRTC` hook to negotiate WebRTC streams and display audio meters.

## 4. Windows 98 Container Images
- Create Dockerfiles for QEMU/PCem/Wine that boot Windows 98 with Lego Loco installed.
- Configure PulseAudio and GStreamer to capture audio/video and publish as WebRTC.
- Ensure each container joins the same virtual LAN using TAP bridges so the games can communicate.

## 5. Kubernetes Deployment
- Write Kubernetes manifests (or a Helm chart) to launch nine emulator pods plus the backend.
- Mount configuration as ConfigMaps so instance addresses are discoverable.
- Expose services so the frontend can reach each WebRTC/VNC stream.

## 6. Healthy Cluster Tests
- Implement scripts under a new `k8s-tests/` directory:
  - `test-network.sh` – verify L2/L3 connectivity between all pods and host.
  - `test-broadcast.sh` – confirm game sessions are visible across containers.
- Integrate these scripts into a CI workflow.

## 7. Web Audio/Video Access
- Extend the streaming pipeline so each emulator's audio and video are available through the browser.
- Provide user controls for muting, volume, and fullscreen per instance.

## 8. VR Interface (Optional)
- Prototype a simple A-Frame or Three.js scene that mirrors the 3×3 grid in VR.
- Connect controller input to the same backend hotkeys.

Each section above represents a major area of missing functionality. Completing them will yield a cluster of Windows 98 containers that communicate with each other, stream audio/video to the web interface, and are verified by automated health tests.
