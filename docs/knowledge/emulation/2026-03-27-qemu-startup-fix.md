# QEMU Startup Fix — 2026-03-27

**Task**: E1 — Fix QEMU startup (P0 blocker)
**Acceptance Criteria**: Health endpoint returns `qemu_healthy: true`

## Root Cause

The health endpoint was **completely non-functional** due to an incompatible
`netcat` flag in `health-monitor.sh`. The backend's `streamQualityMonitor.js`
queries `http://<container>:8080` for health data, but the nc-based HTTP server
inside the container never started — so every health probe returned `null`,
causing `qemu_healthy` to be permanently `false`.

## Bugs Found & Fixed

### 1. CRITICAL — `nc -l -p` incompatible with netcat-openbsd (both health-monitor.sh)

**Files**: `containers/qemu/health-monitor.sh`, `containers/qemu-softgpu/health-monitor.sh`

The Dockerfiles install `netcat-openbsd` (Ubuntu 22.04 default). Its man page
states: *"It is an error to use `-p` in conjunction with `-l`."*

The old code:
```bash
} | nc -l -p "$HEALTH_PORT" -w 1 >/dev/null 2>&1 || true
```
always failed silently (`|| true`), so the health endpoint was never served.

**Fix**: Removed `-p` and `-w` flags (the latter has no effect with `-l` on
netcat-openbsd). Also added proper HTTP carriage returns (`\r\n`) and
`Connection: close` header for spec-compliant responses.

### 2. VGA type mismatch in qemu-softgpu (entrypoint.sh, run-qemu.sh)

**File**: `containers/qemu-softgpu/entrypoint.sh`

Hardware spec requires VMware VGA for SoftGPU drivers. The entrypoint used
`-vga std` (standard VGA), preventing the guest's SoftGPU/VMware SVGA driver
from activating. Display would be stuck in basic VGA mode.

**Fix**: Changed to `-vga vmware` in the softgpu entrypoint and `run-qemu.sh`.

### 3. Missing KVM/TCG accelerator auto-detection (qemu/, qemu-softgpu/)

**Files**: `containers/qemu/entrypoint.sh`, `containers/qemu-softgpu/entrypoint.sh`

QEMU was launched without any `-accel` flag. On hosts with KVM, this wastes
the available hardware acceleration. In CI (no KVM), QEMU defaults to TCG but
emits warnings.

**Fix**: Added auto-detection: checks `/dev/kvm` writability, uses `-accel kvm`
if available, otherwise `-accel tcg`.

### 4. Wrong boot order — `dc` instead of `c`

**Files**: All three entrypoints.

Boot order `dc` means CD-ROM first, then hard disk. No CD-ROM is attached in
the normal flow, so QEMU would waste time probing for a nonexistent CD before
falling back to disk. Also removed `splash-time=5000` which added 5 seconds of
unnecessary delay.

**Fix**: Changed to `-boot order=c,menu=on` (hard disk first).

### 5. Base Dockerfile missing `/images` directory

**File**: `containers/qemu/Dockerfile`

The entrypoint expects `/images/win98.qcow2` to exist. The softgpu Dockerfile
creates this directory, but the base Dockerfile did not. If no volume is mounted,
the entrypoint fails at the disk-image lookup.

**Fix**: Added `RUN mkdir -p /images /opt/builtin-images`.

### 6. Bootable variant — VNC port mismatch & wrong CPU

**File**: `containers/qemu-bootable/entrypoint-bootable.sh`

- QEMU used `-display vnc=:2` (port 5902) but GStreamer rfbsrc connected to
  port 5901. No video frames would ever be captured.
- CPU was `pentium3` instead of spec'd `pentium2`.

**Fix**: Changed VNC display to `:1` and CPU to `pentium2`.

### 7. run-qemu.sh — deprecated `-soundhw` and wrong NIC

**File**: `containers/qemu-softgpu/run-qemu.sh`

Used `-soundhw sb16` (removed in QEMU 9.2) and `-device rtl8139` (spec says
`ne2k_pci`).

**Fix**: Changed to `-device sb16,audiodev=snd0 -audiodev pa,id=snd0` and
`-device ne2k_pci`.

### 8. setup_network.sh — uses `brctl` (not installed) and wrong bridge name

**File**: `containers/qemu-softgpu/setup_network.sh`

Used `brctl addbr br0` which requires `bridge-utils` (not in Dockerfile), and
used bridge name `br0` instead of `loco-br`.

**Fix**: Rewrote to use `ip link` commands consistent with the main entrypoint.

## Health Check Chain

```
Backend (streamQualityMonitor.js)
  → HTTP GET http://<container>:8080
  → health-monitor.sh (nc HTTP server)
  → generate_health_report()
  → get_qemu_health()  →  pgrep qemu-system-i386 → true/false
  → Returns JSON:  { "qemu_healthy": true, ... }
```

## Verification

After these fixes, the health endpoint flow is:
1. `health-monitor.sh` starts `nc -l 8080` (correct netcat-openbsd syntax)
2. Backend connects and gets JSON `{ "qemu_healthy": true, ... }`
3. `analyzeFailureType()` sees `qemu_healthy: true` → no failure
4. Overall status: `healthy`

## Hardware Spec Reference

| Component | QEMU Flag |
|-----------|-----------|
| Machine | `-M pc` (i440FX/PIIX) |
| CPU | `-cpu pentium2` |
| RAM | `-m 512` |
| Disk | `-hda <snapshot>.qcow2` (IDE, 2GB) |
| VGA | `-vga vmware` (SoftGPU) / `-vga std` (base) |
| NIC | `-net nic,model=ne2k_pci` |
| Audio | `-device sb16,audiodev=snd0 -audiodev pa,id=snd0` |
| VNC | `-display vnc=0.0.0.0:1` (port 5901) |
| Accel | `-accel kvm` (host) / `-accel tcg` (CI) |
