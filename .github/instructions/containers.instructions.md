---
description: "Use when editing container Dockerfiles, entrypoint scripts, or QEMU configurations. Covers QEMU flags, Windows 98 guest setup, TAP networking, and PulseAudio pipelines."
applyTo: "containers/**"
---
# Container Development Guidelines

## QEMU Configuration
- QEMU 9.2 with KVM (host) or TCG (CI)
- Hardware: GA686BX, Pentium II, 512MB RAM, 2GB IDE
- Graphics: VMware VGA (SoftGPU) — 1024×768 @ 16bpp
- NIC: ne2k_pci (RTL8029AS) connected to TAP interface
- Audio: SB16 → PulseAudio → GStreamer → UDP:5001
- VNC: 0.0.0.0:590N (N = instance index 0-8)

## Entrypoint Scripts
- Must create TAP interface before starting QEMU
- Attach TAP to `loco-br` bridge
- Start PulseAudio server if audio needed
- Launch QEMU with correct flags for instance index
- Health check: respond to health probes

## Dockerfile Conventions
- Multi-stage builds where possible
- Pin base image versions
- Install only required packages
- QEMU runs as non-root where feasible (needs NET_ADMIN for TAP)
- Copy entrypoint.sh and set as ENTRYPOINT

## Container Variants
- `qemu/` — base QEMU container
- `qemu-softgpu/` — with SoftGPU drivers pre-installed
- `qemu-bootable/` — with bootable disk image
- `wine/` — Wine container (alternative approach)
- `pcem/` — PCem container (image building)

## Knowledge
- Document in `docs/knowledge/emulation/`
