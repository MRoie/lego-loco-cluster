---
name: qemu-emulation
description: 'QEMU emulation for Lego Loco Cluster. Covers QEMU 9.2 hardware config, Windows 98 SE guest, SoftGPU drivers, PulseAudio pipelines, container entrypoints, VNC display, and emulator health.'
---

# QEMU Emulation Skill

## When to Use
- QEMU command-line flag changes
- Container entrypoint modifications
- SoftGPU/VMware VGA config
- PulseAudio/GStreamer audio pipeline
- VNC display configuration
- Emulator health debugging

## Key Files
- `containers/qemu/entrypoint.sh` — base entrypoint
- `containers/qemu-softgpu/` — SoftGPU container
- `containers/qemu-bootable/` — bootable variant
- `config/qemu.json` — QEMU config

## Hardware: GA686BX, Pentium II, 512MB, ne2k_pci, SB16, VMware VGA, 1024×768

## Procedure
1. Check QEMU startup flags and disk image paths
2. Check `docs/knowledge/emulation/` for prior findings
3. Test in local Docker first, then Kind
4. Verify `qemu_healthy: true`
5. Document in `docs/knowledge/emulation/<date>-<topic>.md`

## Tasks: E1 (startup fix P0), E2 (TAP in Kind), E3 (audio pipeline), E4 (hardware docs)
