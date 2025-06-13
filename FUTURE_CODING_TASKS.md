# Future Codex Agent Tasks for Loco LAN

This document lists all remaining work required to accept a Windows 98 image and run the cluster reliably. Each numbered section contains a **prompt** you can copy directly into a future Codex session. Follow the steps in order.

## 0. Onboarding and Setup
**Prompt:**
> "Prepare the development environment for Loco LAN on a fresh Ubuntu machine. Install all required packages and initialize the repo."

Steps:
- Install system packages: `nodejs`, `npm`, `qemu-system-x86`, `qemu-kvm`, `wine`, `gstreamer1.0-tools`, `pulseaudio`, `docker.io`, `tcpdump`.
- Run `npm install` inside both `backend/` and `frontend/`.
- Ensure Docker and a Kubernetes distribution (k3s or kubeadm) are available.

## 1. Image Provisioning
**Prompt:**
> "Create and document a Windows 98 disk image with Lego Loco installed. Provide scripts so containers can load the image automatically."

Tasks:
- Write step-by-step instructions for installing Windows 98 and Lego Loco in an emulator.
- Add a script that converts the install to `win98.qcow2` or `win98.img` for container use.
- Update emulator entrypoints to read an image path from an environment variable.

## 2. Persistent Storage
**Prompt:**
> "Modify the Helm chart so emulator pods mount the disk image from a PersistentVolumeClaim."

Tasks:
- Mount the image via PVC and allow configuration through `values.yaml`.
- Add a toggle for read‑only mode so multiple pods can reuse one base image.

## 3. Cluster Bootstrap Scripts
**Prompt:**
> "Add helper scripts that copy the prepared disk image into the cluster and patch the Helm release automatically."

Tasks:
- Create scripts to upload the image to a volume and update the release with the correct PVC.
- Extend `scripts/start_live_cluster.sh` to call these helpers and regenerate `config/instances.json`.

## 4. Extended Test Coverage
**Prompt:**
> "Expand k8s-tests to verify networking and emulator boot state, and integrate the scripts into CI."

Tasks:
- Enhance `k8s-tests/test-network.sh` with ARP table checks and IPv6 connectivity.
- Add `k8s-tests/test-boot.sh` that waits for each emulator to expose VNC and verifies the Windows desktop.
- Run all tests in CI so failures block merges.

## 5. UI/UX Polishing
**Prompt:**
> "Improve the frontend experience and make the streaming more resilient."

Tasks:
- Allow users to select audio output devices per instance.
- Add reconnect logic to `useWebRTC` for dropped connections.
- Show loading indicators while streams establish.

## 6. VR Interface (Optional)
**Prompt:**
> "Prototype a VR scene that displays the nine video feeds and maps controller buttons to backend hotkeys."

Tasks:
- Build a basic A‑Frame scene showing the grid on a curved surface.
- Wire VR controller events to existing backend hotkey actions.

Completing these prompts will allow the repository to accept a Windows 98 + Lego Loco image and run the full cluster with stable networking, automated tests, and a polished user interface.
