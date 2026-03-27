# QEMU Hardware Reference

**Date**: 2026-03-27
**Author**: @emulation-lead
**Task**: E4
**Status**: complete

## Summary

Complete QEMU hardware configuration reference for Windows 98 SE emulation in the Lego Loco Cluster. Covers every flag used in the production entrypoint (`containers/qemu-softgpu/entrypoint.sh`) with rationale and compatibility notes.

---

## Full QEMU Command Line (Production)

```bash
qemu-system-i386 \
  $ACCEL_FLAG \
  -M pc -cpu pentium2 \
  -m 512 -hda "$SNAPSHOT_NAME" \
  -net nic,model=ne2k_pci,macaddr=$GUEST_MAC \
  -net tap,ifname=$TAP_IF,script=no,downscript=no \
  -device sb16,audiodev=snd0 \
  -vga vmware -display vnc=0.0.0.0:1 \
  -audiodev pa,id=snd0 \
  -rtc base=localtime \
  -boot order=c,menu=on \
  -no-shutdown \
  -no-reboot \
  -monitor none
```

---

## Hardware Configuration (Detailed)

### Machine Type

| Flag | Value | Notes |
|------|-------|-------|
| `-M pc` | i440FX + PIIX3 chipset | The standard PC machine type. Win98 expects this chipset. Do **not** use `-M q35` (ICH9) — Win98 has no drivers for it. |
| `-accel kvm` | KVM hardware acceleration | Use when `/dev/kvm` is available (production). ~10× faster than TCG. |
| `-accel tcg` | Software emulation | Fallback for CI (GitHub Actions) or hosts without KVM. Functional but slow. |

The entrypoint auto-detects KVM: if `/dev/kvm` exists and is writable, it uses KVM; otherwise TCG.

### CPU

| Flag | Value | Notes |
|------|-------|-------|
| `-cpu pentium2` | Pentium II (Deschutes) | Best compatibility with Win98 SE. Supports MMX but not SSE. |
| `-cpu pentium3` | Pentium III (Katmai) | Also works. Adds SSE. Some games may benefit. |
| `-cpu qemu32` | Generic 32-bit | Works but reports unfamiliar CPUID to Win98. Use only if pentium2/3 cause issues. |
| (no `-smp`) | Single core | Win98 does not support SMP. Adding `-smp 2` causes hangs at boot. |

**Recommendation**: Use `-cpu pentium2` for maximum Win98 compatibility. Lego Loco was designed for Pentium II-era hardware.

### Memory

| Flag | Value | Notes |
|------|-------|-------|
| `-m 512` | 512MB RAM | Win98 SE maximum practical RAM. Values above 512MB cause `ESDI_506` bluescreen or boot hang. |

**Limits**: Win98 officially supports up to 512MB. Some patches allow 1GB, but 512MB is safe and sufficient for Lego Loco.

### Storage

| Flag | Value | Notes |
|------|-------|-------|
| `-hda $SNAPSHOT_NAME` | Primary IDE drive (QCOW2) | Legacy syntax; equivalent to `-drive file=...,format=qcow2,if=ide,index=0`. |
| QCOW2 format | Copy-on-write disk image | Enables snapshots (`savevm`/`loadvm`) and backing-file overlays. |
| `-drive file=...,format=qcow2,if=ide` | Explicit form | Use this if you need to set additional options like `cache=writeback`. |

**Snapshot strategy**: The entrypoint creates a COW overlay (`qemu-img create -f qcow2 -b $DISK -F qcow2 $SNAPSHOT_NAME`) so each instance writes to its own file while sharing a read-only base.

### Video / Display

| Flag | Value | Notes |
|------|-------|-------|
| `-vga vmware` | VMware SVGA adapter | Required for SoftGPU driver. Provides 2D/3D acceleration in guest via VMware SVGA II. |
| `-vga cirrus` | Cirrus Logic GD5446 | Fallback if SoftGPU is not installed. Limited to 2D only, max 1024×768×16bpp. |
| `-vga std` | Bochs/VBE VGA | Another fallback. Supports high resolutions but no 3D. |
| `-display vnc=0.0.0.0:1` | VNC server on port 5901 | Each pod exposes VNC on display `:1` (port 5901). GStreamer captures from this VNC for WebRTC streaming. |

**Resolution**: 1024×768 at 16bpp (65536 colors). Set in Windows 98 Display Properties after SoftGPU driver installation. The GStreamer pipeline (`rfbsrc`) captures at this resolution.

### Audio

| Flag | Value | Notes |
|------|-------|-------|
| `-device sb16,audiodev=snd0` | Sound Blaster 16 (ISA) | Win98 has built-in SB16 drivers. Lego Loco uses DirectSound which maps to SB16. |
| `-audiodev pa,id=snd0` | PulseAudio backend | Connects QEMU audio output to PulseAudio running in the container. |

**Audio pipeline (full path)**:
```
Lego Loco (DirectSound) → Win98 SB16 driver → QEMU sb16 device
  → PulseAudio daemon → GStreamer (opusenc) → UDP:5001
  → WebRTC audio track → Browser
```

**Alternatives**: `-audiodev sdl` (requires SDL), `-audiodev alsa` (requires ALSA). PulseAudio is preferred in containers because it runs in userspace.

### Network Interface Card (NIC)

| Flag | Value | Notes |
|------|-------|-------|
| `-net nic,model=ne2k_pci,macaddr=$GUEST_MAC` | NE2000-compatible PCI NIC | Win98 has a built-in RTL8029AS (NE2000 PCI) driver. MAC address is per-instance (L2 spec). |
| `-net tap,ifname=$TAP_IF,script=no,downscript=no` | TAP backend | Connects to the `loco-br` bridge inside the pod. `script=no` avoids running setup scripts (entrypoint handles bridge/TAP setup). |

**MAC scheme**: `52:54:00:10:00:0N` where N is the instance index (0–8). The `52:54:00` prefix is QEMU's locally-administered OUI.

**Alternative NIC models**:

| Model | Flag | Win98 Driver | Notes |
|-------|------|-------------|-------|
| ne2k_pci | `model=ne2k_pci` | Built-in RTL8029AS | **Recommended**. Zero driver installation. |
| rtl8139 | `model=rtl8139` | Needs INF from Realtek | Works but requires manual driver install. |
| e1000 | `model=e1000` | No Win98 driver | Do not use. |
| pcnet | `model=pcnet` | Built-in AMD PCnet | Alternative to ne2k_pci; also zero-install. |

### Input

| Component | Notes |
|-----------|-------|
| PS/2 Keyboard | Default in `-M pc`. Win98 expects PS/2. Do not add USB keyboard — Win98 needs specific USB drivers. |
| PS/2 Mouse | Default. VNC injects mouse events as PS/2 input. |

### Boot Configuration

| Flag | Value | Notes |
|------|-------|-------|
| `-rtc base=localtime` | RTC synced to host local time | Win98 expects the hardware clock in local time, not UTC. |
| `-boot order=c,menu=on` | Boot from hard disk, enable boot menu | `c` = first hard disk. `menu=on` allows pressing F12 for boot device selection. |
| `-no-shutdown` | Prevent QEMU exit on guest shutdown | Keeps the process alive so the health monitor can detect shutdown and restart. |
| `-no-reboot` | Prevent automatic reboot on guest crash | Avoids infinite reboot loops on bluescreen. |
| `-monitor none` | Disable QEMU monitor console | Prevents accidental input to the monitor. Use QMP socket instead for programmatic control. |

---

## Network Configuration (Summary)

| Parameter | Value |
|-----------|-------|
| Bridge | `loco-br` at `192.168.10.1/24` |
| TAP interface | `tap{N}` (per instance index) |
| Guest IP | `192.168.10.(10+N)` (static) |
| Guest MAC | `52:54:00:10:00:0{N}` |
| Guest gateway | `192.168.10.1` |
| Guest netmask | `255.255.255.0` |
| Workgroup | `LOCOLAND` |
| Game ports | TCP/UDP 2300 (DirectPlay), TCP 47624 (DirectPlay helper) |

See `docs/knowledge/lan-networking/instance-identity-spec.md` for the full identity injection pipeline.

---

## Display Settings
- Resolution: 1024×768
- Color depth: 16bpp (65536 colors)
- Refresh: 60Hz via VNC
- GStreamer capture: `rfbsrc host=127.0.0.1 port=5901` → VP8 encode → WebRTC

---

## Audio Pipeline
```
Lego Loco (DirectSound) → Win98 SB16 driver → QEMU sb16 device
  → PulseAudio (-audiodev pa) → GStreamer (opusenc) → UDP:5001
  → WebRTC audio track → Browser speaker
```

---

## Acceleration

| Mode | Flag | When | Performance |
|------|------|------|-------------|
| KVM | `-accel kvm` | Production, `/dev/kvm` available | ~native speed |
| TCG | `-accel tcg` | CI, no KVM access | ~5-10× slower, functional |

The entrypoint auto-selects:
```bash
if [ -e /dev/kvm ] && [ -w /dev/kvm ]; then
  ACCEL_FLAG="-accel kvm"
else
  ACCEL_FLAG="-accel tcg"
fi
```

---

## QEMU Monitor Commands

| Command | Purpose |
|---------|---------|
| `system_powerdown` | Send ACPI shutdown signal (graceful) |
| `system_reset` | Hard reset (like pressing reset button) |
| `sendkey ctrl-alt-delete` | Send Ctrl+Alt+Del to guest |
| `savevm <name>` | Create named snapshot |
| `loadvm <name>` | Restore named snapshot |
| `info snapshots` | List all snapshots |
| `info network` | Show network interfaces |
| `info block` | Show block devices |
| `info status` | Show VM running/paused state |
| `screendump <file>` | Capture VNC screen to PPM file |

---

## QEMU Version Compatibility

| QEMU Version | Status | Notes |
|--------------|--------|-------|
| 8.2.x | **Recommended** | Stable, all features work. Used in `qemu-softgpu` Docker image. |
| 8.0–8.1 | Works | Minor VNC performance differences. |
| 7.x | Works | Older PulseAudio backend syntax (`-audiodev pa,id=snd0` still valid). |
| 6.x | Caution | `-vga vmware` had rendering bugs affecting SoftGPU. Upgrade if possible. |
| 5.x and older | Not supported | Missing `vmware-svga` improvements, older NIC emulation. |
| 9.0+ | Untested | May work but TCG changes could affect Win98 timing-sensitive code (e.g., game loops). Test before upgrading. |

### Known Issues

1. **QEMU 6.x + VMware SVGA**: Cursor corruption in 1024×768×16bpp mode. Fixed in 7.0.
2. **TCG + Win98 boot timing**: Some QEMU versions boot Win98 too fast for the BIOS POST, causing "keyboard not found" errors. Add `-rtc base=localtime` and ensure BIOS timeout is adequate.
3. **PulseAudio in containers**: Must start `pulseaudio --start --exit-idle-time=-1` before QEMU. Default idle timeout of 20s will kill the daemon during quiet periods.
4. **SB16 + `-audiodev` syntax**: Older QEMU used `-soundhw sb16`. Modern QEMU requires `-device sb16,audiodev=snd0 -audiodev pa,id=snd0`.
5. **ne2k_pci MAC reset**: If the guest OS re-initializes the NIC (e.g., after driver reinstall), it reads the MAC from QEMU's emulated EEPROM, which matches the `-net nic,macaddr=...` value.

---

## Config File Reference

The project stores hardware defaults in `config/qemu.json`:

```json
{
  "hardware": {
    "machine": "pc",
    "cpu": "pentium2",
    "memory_mb": 512,
    "disk_size": "2G",
    "disk_format": "qcow2",
    "disk_interface": "ide",
    "vga": "vmware",
    "nic": "ne2k_pci",
    "audio": "sb16",
    "audio_backend": "pa"
  },
  "display": {
    "vnc_base_port": 5900,
    "vnc_display_offset": 1,
    "resolution": "1024x768",
    "color_depth": 16
  }
}
```

## Cross-References

- **L2**: `docs/knowledge/lan-networking/instance-identity-spec.md` — NIC/MAC/IP scheme
- **L7**: `docs/knowledge/lan-networking/2026-03-27-dhcp-collision-prevention.md` — why static IPs
- **W6**: `docs/knowledge/win98-image/shutdown-restart.md` — monitor commands for recovery
- **Entrypoint**: `containers/qemu-softgpu/entrypoint.sh` — actual QEMU startup command
