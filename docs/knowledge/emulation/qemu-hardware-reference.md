# QEMU Hardware Reference

**Date**: 2025-01-24
**Author**: @emulation-lead
**Task**: E4
**Status**: finding

## Summary
QEMU hardware configuration reference for Windows 98 SE emulation in the Lego Loco Cluster.

## Hardware Configuration

| Component | Value | QEMU Flag |
|-----------|-------|-----------|
| Machine | GA686BX (440BX chipset) | `-machine pc` |
| CPU | Pentium II 300MHz | `-cpu pentium2` or `-cpu qemu32` |
| RAM | 512MB | `-m 512` |
| Storage | 2GB IDE (QCOW2) | `-hda /path/to/disk.qcow2` |
| Display | VMware VGA (SoftGPU) | `-device vmware-svga` or `-vga vmware` |
| Display (fallback) | Cirrus VGA | `-vga cirrus` |
| NIC | RTL8029AS (ne2k_pci) | `-device ne2k_pci,netdev=net0` |
| Audio | Sound Blaster 16 | `-device sb16` |
| VNC | Per instance (port 5900+N) | `-display vnc=0.0.0.0:N` |

## Network Configuration

| Parameter | Value |
|-----------|-------|
| Network backend | TAP interface | 
| QEMU flag | `-netdev tap,id=net0,ifname=tapN,script=no,downscript=no` |
| Bridge | loco-br (192.168.10.1/24) |
| Instance IP range | 192.168.10.10 - 192.168.10.18 |

## Display Settings
- Resolution: 1024×768
- Color depth: 16bpp (65536 colors)
- Refresh: 60Hz via VNC

## Audio Pipeline
```
Win98 SB16 → QEMU audio → PulseAudio → GStreamer → UDP:5001 → WebRTC audio track
```

## Acceleration
- **Host (production)**: KVM (`-accel kvm`)
- **CI (GitHub Actions)**: TCG (`-accel tcg`)
- KVM requires `/dev/kvm` device access in container

## Common QEMU Monitor Commands
| Command | Purpose |
|---------|---------|
| `system_powerdown` | Send ACPI shutdown signal |
| `system_reset` | Hard reset |
| `sendkey ctrl-alt-delete` | Send Ctrl+Alt+Del to guest |
| `savevm <name>` | Create named snapshot |
| `loadvm <name>` | Restore named snapshot |
| `info snapshots` | List all snapshots |
| `info network` | Show network interfaces |
| `info block` | Show block devices |
