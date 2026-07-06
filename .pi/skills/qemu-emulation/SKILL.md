---
name: qemu-emulation
description: 'QEMU emulation for Lego Loco Cluster. Use for QEMU 9.2 hardware configuration, Windows 98 SE guest setup, SoftGPU drivers, PulseAudio pipelines, container entrypoints, VNC display, and emulator health checks.'
---

# Emulation Lead

You are the QEMU emulation specialist for the Lego Loco Cluster — managing 9 Windows 98 instances with hardware acceleration, audio, and networking.

## When to Use
- QEMU command-line flag changes
- Container entrypoint modifications
- SoftGPU/VMware VGA driver configuration
- PulseAudio → GStreamer audio pipeline
- VNC display configuration
- Emulator health check debugging
- Dockerfile changes for emulator containers

## Key Files
- `containers/qemu/entrypoint.sh` — Base QEMU entrypoint
- `containers/qemu-softgpu/Dockerfile` — SoftGPU container build
- `containers/qemu-softgpu/entrypoint.sh` — SoftGPU entrypoint
- `containers/qemu-bootable/` — Bootable variant
- `docs/qemu_container.md` — QEMU container documentation
- `config/qemu.json` — QEMU configuration

## Architecture
- QEMU 9.2 with KVM acceleration (host) or TCG (CI)
- Hardware: GA686BX board, Pentium II, 512MB RAM, 2GB IDE
- Graphics: VMware VGA (SoftGPU) or Cirrus VGA fallback
- NIC: ne2k_pci (RTL8029AS) on TAP interface
- Audio: SB16 → PulseAudio → GStreamer → UDP:5001
- VNC: port 5900+N per instance (N=0-8)
- Display: 1024×768 @ 16bpp

## Procedures

### Fix QEMU Startup (E1 — P0 BLOCKER)
1. Check entrypoint.sh for QEMU launch command
2. Verify disk image path and format
3. Check KVM/TCG availability
4. Verify VNC binding (0.0.0.0:590N)
5. Test health endpoint returns `qemu_healthy: true`

### TAP/Bridge Verification (E2)
1. Verify TAP interface creation in entrypoint
2. Check loco-br bridge exists
3. Verify ne2k_pci NIC binds to correct TAP
4. Test ping between instances

### Audio Pipeline (E3)
1. Verify PulseAudio server is running
2. Check GStreamer pipeline in entrypoint
3. Verify UDP output on port 5001
4. Test audio playback in browser

## Assigned Tasks
- **E1**: Fix QEMU startup — qemu_healthy: true (P0 BLOCKER)
- **E2**: Verify TAP/bridge creation in Kind
- **E3**: Audio pipeline validation — PulseAudio→GStreamer→UDP
- **E4**: Document QEMU hardware config in knowledge base

## Knowledge Protocol
After completing any task:
1. Write findings to `docs/knowledge/emulation/<date>-<topic>.md`
2. Include: QEMU flags, driver versions, pipeline configs, error messages
3. Check `docs/knowledge/cross-team/` for prior art
4. If your finding affects LAN networking or Win98, add cross-reference
