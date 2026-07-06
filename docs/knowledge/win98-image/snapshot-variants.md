# QCOW2 Snapshot Variant Matrix

**Date**: 2026-03-27
**Author**: @win98-lead
**Task**: W5
**Status**: spec

## Summary

This document defines the QCOW2 snapshot variants for the Lego Loco Cluster. Each variant builds on its parent, adding specific software and configuration. The chain ensures reproducible, minimal images that can be reverted cleanly.

## Snapshot Chain

```
base-install
  └── lego-loco
        └── multiplayer-ready
```

Each child snapshot is created after its parent is fully verified. Reverting to a parent discards all child changes.

---

## Variant Definitions

### 1. `base-install` — Clean Windows 98SE + Drivers

**Parent**: Raw QCOW2 converted from PCem VHD
**What's added**:
- Windows 98 Second Edition (clean install, OEM)
- SoftGPU / VMware SVGA driver (1024×768, 16-bit color confirmed)
- NE2000-compatible NIC driver (ne2k_pci / RTL8029AS)
- Sound Blaster 16 audio driver
- VESA VBE fallback driver
- Generic IDE controller (PIIX4)
- Microsoft TCP/IP protocol stack installed
- NetBIOS over TCP/IP enabled

**Verification checklist**:
- [ ] Device Manager shows no yellow bangs (unknown devices)
- [ ] Display: 1024×768 @ 16-bit via `dxdiag`
- [ ] Network adapter present in Device Manager
- [ ] `winipcfg` launches and shows adapter
- [ ] Sound plays via `C:\Windows\Media\tada.wav`
- [ ] Disk free space > 500 MB

**Known issues**:
- SoftGPU may require manual display mode switch after first boot
- NE2000 driver occasionally needs manual IRQ assignment (IRQ 10)

---

### 2. `lego-loco` — Base + Lego Loco Installed

**Parent**: `base-install`
**What's added**:
- Lego Loco game (full CD install to `C:\Program Files\LEGO Media\LEGO Loco\`)
- DirectX 6.1 (bundled with game installer)
- Desktop shortcut: "LEGO Loco"
- Start Menu entry: Start → Programs → LEGO Media → LEGO Loco
- DirectPlay service provider registered (TCP/IP)
- CD-ROM drive letter configured (D:\ or as assigned by QEMU)

**Verification checklist**:
- [ ] Desktop shortcut launches game to main menu
- [ ] Intro video plays (or skips with Esc)
- [ ] Single-player "New Town" loads without crash
- [ ] Sound effects and music audible
- [ ] Multiplayer menu accessible (Host/Join options visible)
- [ ] `dxdiag` → DirectPlay tab shows TCP/IP provider

**Known issues**:
- Game may request CD on launch — ensure ISO is mounted as QEMU CD-ROM
- DirectX 6.1 installer may prompt for reboot; snapshot only after reboot completes
- If SoftGPU 3D acceleration isn't detected, game falls back to software renderer (playable but slower)

---

### 3. `multiplayer-ready` — Lego Loco + Network Identity Configured

**Parent**: `lego-loco`
**What's added**:
- Static IP address: `192.168.10.(10 + N)` where N = instance index (0–8)
- Subnet mask: `255.255.255.0`
- Gateway: `192.168.10.1`
- Computer Name: `LOCO-0N` (e.g., `LOCO-00` through `LOCO-08`)
- Workgroup: `LOCOLAND`
- NetBIOS over TCP/IP: enabled
- File and Printer Sharing: enabled (for Network Neighborhood visibility)
- DirectPlay TCP/IP service provider: configured

**Important**: This variant is **per-instance**. Each of the 9 instances has its own `multiplayer-ready` snapshot with unique identity fields. See `docs/knowledge/lan-networking/instance-identity-spec.md` for the full identity table.

**Verification checklist**:
- [ ] `winipcfg` shows correct static IP for this instance
- [ ] `ping 192.168.10.1` (gateway) succeeds
- [ ] `ping 192.168.10.XX` (another instance) succeeds
- [ ] Network Neighborhood shows other instances by hostname
- [ ] Computer Name matches expected `LOCO-0N`
- [ ] Lego Loco → Multiplayer → Host creates a session
- [ ] Lego Loco → Multiplayer → Join discovers sessions from other instances

**Known issues**:
- Win98 TCP/IP requires reboot after changing Computer Name or IP
- NetBIOS name cache may be stale after snapshot revert — run `nbtstat -R` to purge
- If DHCP was previously configured, static IP won't take effect until DHCP is fully disabled and system rebooted
- Network Neighborhood browse list can take 1–3 minutes to populate after boot

---

## Variant Matrix

| Variant | Parent | What's Added | Approx Size | Per-Instance? | Known Issues |
|---------|--------|-------------|-------------|---------------|--------------|
| `base-install` | Raw QCOW2 | Win98SE + SoftGPU + NE2K + SB16 drivers | ~800 MB | No (shared) | SoftGPU mode switch, NE2K IRQ |
| `lego-loco` | `base-install` | Lego Loco + DirectX 6.1 + DirectPlay | ~1.1 GB | No (shared) | CD mount required, DX reboot |
| `multiplayer-ready` | `lego-loco` | Static IP + hostname + workgroup + NetBIOS | ~1.1 GB (delta ~5 MB) | **Yes** (×9) | Name cache stale, DHCP conflict |

**Total storage for 9 instances**: ~800 MB (base) + ~300 MB (lego-loco delta) + 9 × ~5 MB (multiplayer-ready deltas) ≈ **1.15 GB** using QCOW2 backing chains.

---

## Snapshot Operations

### Creating a snapshot
```bash
# Inside QEMU monitor (Ctrl-Alt-2 or via QMP)
savevm base-install
savevm lego-loco
savevm multiplayer-ready
```

### Listing snapshots
```bash
qemu-img snapshot -l win98.qcow2
```

### Reverting to a snapshot
```bash
# QEMU monitor
loadvm base-install    # Reverts to clean Win98 + drivers
loadvm lego-loco       # Reverts to clean game install
loadvm multiplayer-ready  # Reverts to configured network state
```

### Using QCOW2 backing chains (alternative to internal snapshots)
```bash
# Create base
qemu-img create -f qcow2 base-install.qcow2 2G

# Create lego-loco overlay backed by base
qemu-img create -f qcow2 -b base-install.qcow2 -F qcow2 lego-loco.qcow2

# Create per-instance multiplayer-ready overlay
qemu-img create -f qcow2 -b lego-loco.qcow2 -F qcow2 multiplayer-ready-00.qcow2
qemu-img create -f qcow2 -b lego-loco.qcow2 -F qcow2 multiplayer-ready-01.qcow2
# ... through 08
```

Backing chains are preferred for Kubernetes deployments because the shared base layers only need to exist once in the PersistentVolume, and per-instance overlays are tiny.

---

## Future Variants (Planned)

| Variant | Parent | Purpose | Status |
|---------|--------|---------|--------|
| `safe-mode` | `base-install` | Boots directly into Safe Mode for debugging | Planned |
| `benchmark` | `lego-loco` | Game loaded with known town for perf testing | Planned |
| `recording-ready` | `multiplayer-ready` | Pre-configured for video capture/export | Planned |

---

## References

- [Instance Identity Spec](../lan-networking/instance-identity-spec.md) — per-instance network identity fields
- [Shutdown/Restart Procedure](shutdown-restart.md) — safe snapshot and revert operations
- [Image Creation Workflow](image-creation-workflow.md) — PCem → QCOW2 pipeline
- [Storage Strategy](../../../docs/STORAGE_STRATEGY.md) — persistent volume and image distribution
