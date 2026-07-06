# Per-Instance Win98 Image Customization

**Date**: 2026-03-27  
**Author**: @win98-lead  
**Task**: W4  
**Status**: implemented  

## Summary

Created `scripts/customize-win98-instance.sh` to generate unique-per-instance Windows 98 identity configuration. Each of the 9 QEMU instances (index 0–8) receives a deterministic registry patch, boot script, and LMHOSTS file derived from the identity scheme defined in [instance-identity-spec.md](../lan-networking/instance-identity-spec.md).

## What the script produces

| Artifact | Purpose |
|----------|---------|
| `LOCO-ID-N.REG` | Windows 98 registry patch setting ComputerName, Workgroup, static IP, and NetBIOS options |
| `LOCO-ID-N.BAT` | AUTOEXEC-callable batch script that applies the .reg and writes a marker file |
| `LMHOSTS-N` | Static NetBIOS name table mapping all 9 instances (fallback for broadcast failures) |

All files use DOS (CR+LF) line endings for Windows 98 compatibility.

## Registry keys patched

```
HKLM\System\CurrentControlSet\Services\VxD\VNETSUP
  ComputerName = LOCO-0N
  Workgroup    = LOCOLAND

HKLM\System\CurrentControlSet\Services\Class\NetTrans\0000
  IPAddress      = 192.168.10.(10+N)
  IPMask         = 255.255.255.0
  DefaultGateway = 192.168.10.1

HKLM\System\CurrentControlSet\Services\VxD\MSTCP
  EnableDNS           = 0
  BcastNameQueryCount = 3
  NodeType            = 8   (hybrid — broadcast + WINS)
```

## Injection strategies

The script supports three ways to apply the configuration:

1. **File output** (`-o DIR`) — write .reg/.bat/LMHOSTS to a directory, then mount as a QEMU floppy image or 9pfs share. The guest AUTOEXEC.BAT calls `REGEDIT /S A:\LOCO-ID.REG` at boot.
2. **virt-customize** (`-d IMAGE`) — inject files directly into a QCOW2 image and register a firstboot command. Requires `libguestfs-tools`.
3. **stdout** (default) — print all artifacts for inspection or piping.

### Recommended flow (runtime patching)

```
entrypoint.sh
  ├── customize-win98-instance.sh $N -o /tmp/identity
  ├── mkdosfs + mcopy → create floppy.img with .reg + LMHOSTS
  └── qemu-system-i386 ... -fda /tmp/floppy.img
```

The guest base image's AUTOEXEC.BAT includes:
```bat
IF EXIST A:\LOCO-ID.REG REGEDIT /S A:\LOCO-ID.REG
IF EXIST A:\LMHOSTS COPY A:\LMHOSTS C:\WINDOWS\LMHOSTS
```

## Relationship to entrypoint.sh

The current `containers/qemu-softgpu/entrypoint.sh` already derives identity env vars (`GUEST_HOSTNAME`, `GUEST_IP`, `GUEST_MAC`, etc.) from `INSTANCE_INDEX`. This script complements it by generating the **guest-side** (Windows 98) configuration that must exist inside the VM to match the host-side QEMU settings.

## Lessons learned

- Windows 98 registry files must start with `REGEDIT4` (not `Windows Registry Editor Version 5.00`).
- The `NetTrans\0000` key path is adapter-specific; if the NE2000 driver binds at a different index, the key may differ. The base image should be built with the NIC as the first (and only) network adapter.
- NodeType=8 (h-node) tells Windows to try WINS first, then fall back to broadcast — optimal for a small LAN without a dedicated WINS server.
