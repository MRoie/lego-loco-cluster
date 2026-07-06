# Win98 Image Creation Workflow — Complete Pipeline

**Date**: 2026-03-27  
**Author**: @win98-lead  
**Task**: W1 — Document complete image creation workflow  
**Status**: active

---

## Overview

This document describes the end-to-end pipeline for creating a Windows 98 SE + Lego Loco disk image, converting it for QEMU, and integrating it into the Lego Loco Cluster. The pipeline is:

```
PCem (GA686BX, Pentium II, 512 MB, Voodoo 3D)
  → Win98 SE install
    → Drivers (SoftGPU, RTL8029, SB16)
      → Lego Loco install
        → VHD export
          → qemu-img convert -f vpc -O qcow2
            → QEMU boot verification
              → Snapshot creation & registry push
```

**Estimated disk requirements**: ~2 GB raw, ~600–800 MB qcow2 compressed.

---

## 1. Prerequisites

### 1.1 Software

| Tool | Version / Notes | Purpose |
|------|----------------|---------|
| **PCem** | v17 or later | Initial image creation in accurate hardware emulation |
| **QEMU** | 7.x+ (`qemu-system-i386`, `qemu-img`) | Conversion, verification, and production runtime |
| **Docker** | 20.10+ | Container image builds |
| **skopeo** or **crane** | Latest | OCI snapshot pushing/pulling (optional for registry workflow) |

### 1.2 ISOs & Media

| Media | Notes |
|-------|-------|
| **Windows 98 SE** ISO | Must be Second Edition (4.10.2222); First Edition lacks USB and driver fixes |
| **Lego Loco** CD/ISO | Original disc image; autorun may not trigger — use `D:\setup.exe` directly |
| **SoftGPU** driver package | Provides VMware SVGA II compatible driver for Win98 ([GitHub: JHRobotics/softgpu](https://github.com/JHRobotics/softgpu)) |
| **RTL8029AS** driver disk | Realtek NE2000-compatible PCI NIC driver (maps to QEMU `ne2k_pci` model) |
| **SB16 drivers** | Usually auto-detected by Win98 SE; included on the Win98 CD under `drivers\audio` |

### 1.3 Target Hardware Profile

From [config/qemu.json](../../../config/qemu.json):

```json
{
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
}
```

The PCem configuration must match this hardware profile so drivers installed in PCem remain valid under QEMU.

---

## 2. Phase 1 — PCem Machine Setup

### 2.1 Create New Machine

1. Open PCem → **File → New**.
2. Configure the following:

| Setting | Value | Why |
|---------|-------|-----|
| Motherboard | **GA686BX** (Intel 440BX) | Stable Pentium II chipset, well-supported by Win98 SE |
| CPU | **Pentium II 300 MHz** | Matches `pentium2` in QEMU config |
| RAM | **512 MB** | Matches `memory_mb: 512` in QEMU config |
| HDD | **IDE, 2 GB** | Matches `disk_size: "2G"` — create as a new blank image |
| Graphics | **Voodoo 3D** (temporary) | Used during Win98 install only; will be replaced by SoftGPU |
| Sound | **Sound Blaster 16** | Matches `audio: "sb16"` |
| Network | **Realtek RTL8029AS** | Matches `nic: "ne2k_pci"` |
| CD-ROM | **IDE CD-ROM** | Needed to mount Win98 ISO and Lego Loco ISO |

### 2.2 BIOS Settings

1. Boot into BIOS (Del key at POST).
2. Set boot order: **CD-ROM → HDD**.
3. Ensure IDE channels are auto-detecting (Primary Master = HDD, Secondary Master = CD-ROM).
4. Save & Exit.

### 2.3 Attach Win98 SE ISO

- PCem → **CD-ROM → Image → Browse** → Select the Win98 SE ISO.

---

## 3. Phase 2 — Windows 98 SE Installation

### 3.1 Boot & Partition

1. Boot from the Win98 SE CD.
2. At the startup menu, choose **"Boot from CD-ROM"**.
3. Select **"Start Windows 98 Setup from CD-ROM"**.
4. When prompted for disk preparation:
   - Run `FDISK` → Create a single **Primary DOS Partition** using the full 2 GB.
   - **Important**: Use **FAT32** (Large Disk Support = Yes). Win98 does NOT support NTFS.
5. Reboot and format the partition (`FORMAT C: /S` is done by setup).

### 3.2 Run Setup

1. Setup will copy files, detect hardware, and configure components.
2. Choose **Typical** installation.
3. Set computer name to `LOCO-NODE` (or any consistent name).
4. Set workgroup to `LOCO` for DirectPlay LAN discovery.
5. Do **not** create a startup disk when prompted.

### 3.3 First Boot & Configuration

1. After reboot, complete the first-boot wizard (timezone, user info).
2. Let Windows detect Plug & Play hardware — dismiss any "driver not found" prompts for now.
3. Verify: Desktop loads with Start menu → right-click My Computer → Properties shows **Windows 98 SE 4.10.2222**.

> **Tip**: If setup hangs at hardware detection, try disabling Voodoo 3D temporarily and use standard VGA.

---

## 4. Phase 3 — Driver Installation

**Installation order matters.** Install in this sequence to avoid conflicts:

### 4.1 SoftGPU Display Driver (VMware SVGA II)

1. Mount the SoftGPU driver disk/ISO in PCem.
2. Run the SoftGPU installer (`SOFTGPU.EXE`).
3. Select **VMware SVGA II** when prompted for driver type.
4. Reboot when prompted.
5. After reboot, the Voodoo 3D will be replaced by VMware SVGA.

**Verification**:
- Right-click Desktop → **Properties → Settings** tab.
- Set resolution to **1024×768** and color depth to **16-bit (High Color)**.
- Click **Apply** → confirm the display is correct.
- Device Manager → Display adapters → should show **VMware SVGA II**.

**If SoftGPU fails**: Fall back to VESA VBE driver (limited to 800×600). See [known-driver-issues.md](known-driver-issues.md).

### 4.2 RTL8029AS Network Driver

1. Go to **Control Panel → Add New Hardware**.
2. Choose **"No, I want to select the hardware from a list"**.
3. Select **Network adapters** → **Have Disk** → point to the RTL8029 driver folder.
4. Select **Realtek RTL8029(AS)** and complete the wizard.
5. Reboot when prompted.

**Verification**:
- Device Manager → Network adapters → **Realtek RTL8029(AS)** (no yellow exclamation).
- Start → Run → `winipcfg` → adapter appears and can obtain an IP.

> **Note**: The QEMU model `-device ne2k_pci` presents as RTL8029AS to the guest OS. The driver name in Windows is "Realtek RTL8029(AS)".

### 4.3 SB16 Audio Driver

Sound Blaster 16 is typically auto-detected by Windows 98 SE. If not:

1. Control Panel → Add New Hardware → let Windows scan.
2. If prompted, point to the Win98 CD drivers directory.

**Verification**:
- Device Manager → Sound, video and game controllers → **Creative SB16** (no conflicts).
- Open `C:\Windows\Media\tada.wav` — sound should play.

> **Note**: DMA/IRQ conflicts can occur. If Device Manager shows a yellow icon, go to Properties → Resources and adjust manually (IRQ 5, DMA 1, DMA 5 are standard SB16 defaults).

### 4.4 Post-Driver Checklist

Open Device Manager and confirm **zero yellow exclamation marks** on:

- [x] Display adapters → VMware SVGA II
- [x] Network adapters → Realtek RTL8029(AS)
- [x] Sound → Creative SB16
- [x] No unknown devices remaining

---

## 5. Phase 4 — Lego Loco Installation

### 5.1 Install

1. Mount the Lego Loco CD/ISO in PCem's CD-ROM drive.
2. If autorun triggers, follow prompts. Otherwise, open **My Computer → D:\ → `SETUP.EXE`**.
3. Accept defaults — installs to `C:\Program Files\LEGO Media\LEGO Loco`.
4. A desktop shortcut should be created automatically; if not, create one manually:
   - Target: `C:\Program Files\LEGO Media\LEGO Loco\LOCO.EXE`

### 5.2 First Launch Verification

1. Double-click the **LEGO Loco** desktop icon.
2. The intro video should play (skip with Esc).
3. Main menu should render at 1024×768 with proper colors.
4. Select **Play → New Town** → verify the game world loads.
5. Press Esc → Exit to quit cleanly.

### 5.3 Network Configuration (for Multiplayer)

Configure TCP/IP for the cluster's LAN bridge:

1. Control Panel → Network → TCP/IP (bound to RTL8029AS) → Properties.
2. Set to **"Obtain an IP address automatically"** (DHCP from bridge) or static:
   - IP: `192.168.10.XXX` (where XXX = instance number + 10)
   - Subnet: `255.255.255.0`
   - Gateway: `192.168.10.1` (bridge address)
3. Identification tab → Computer Name: `LOCO-NODE` / Workgroup: `LOCO`.

DirectPlay ports used by Lego Loco:
- **TCP/UDP 2300** — Game traffic
- **UDP 47624** — DirectPlay session discovery

---

## 6. Phase 5 — VHD Export from PCem

### 6.1 Clean Shutdown

1. Inside Windows 98: **Start → Shut Down → Shut Down**.
2. Wait for the "It's now safe to turn off your computer" screen.
3. Power off the PCem VM.

### 6.2 Locate the Disk Image

PCem stores hard disk images in its configuration directory:

- **Windows**: `%APPDATA%\PCem\`
- **Linux**: `~/.pcem/`

The file will typically be named after the machine, e.g., `LOCO-NODE.img` or `LOCO-NODE.vhd`.

### 6.3 Copy to Working Directory

```bash
# Copy from PCem's directory to your working area
cp ~/.pcem/LOCO-NODE.img ./disk_image.vhd
```

> **Important**: PCem may produce `.img` files that are actually VHD format internally. Test with `qemu-img info` to confirm the detected format.

---

## 7. Phase 6 — QCOW2 Conversion

### 7.1 Identify the Source Format

```bash
qemu-img info disk_image.vhd
```

Look for the `file format:` line. Common values:
- `vpc` — VHD format (PCem default for VHD exports)
- `raw` — Raw disk image
- `vmdk` — VMware format (rare from PCem)

### 7.2 Convert to QCOW2

**Linux / WSL**:

```bash
# Using the project's build script (recommended):
./scripts/create_win98_image.sh --disk-image /path/to/disk_image.vhd --output-dir ./images

# Manual conversion:
qemu-img convert -f vpc -O qcow2 disk_image.vhd win98.qcow2

# Also create a raw backup for archival:
qemu-img convert -f vpc -O raw disk_image.vhd win98.img
```

**Windows (PowerShell)**:

```powershell
.\scripts\create_win98_image.ps1 C:\path\to\disk_image.vhd C:\output\dir
```

### 7.3 Verify Conversion

```bash
qemu-img info win98.qcow2
```

Expected output:
```
file format: qcow2
virtual size: 2 GiB (2147483648 bytes)
disk size: 600-800 MiB
cluster_size: 65536
```

Confirm:
- `file format` is `qcow2`
- `virtual size` is ~2 GiB
- `disk size` is reasonable (not 0, not equal to virtual size)

### 7.4 Integrity Check

```bash
qemu-img check win98.qcow2
```

Should report `No errors were found on the image`.

---

## 8. Phase 7 — QEMU Boot Verification

### 8.1 Quick Smoke Test

Boot the image directly with QEMU matching the production hardware config:

```bash
qemu-system-i386 \
  -M pc -cpu pentium2 \
  -m 512 \
  -hda win98.qcow2 \
  -device ne2k_pci,netdev=net0 \
  -netdev user,id=net0 \
  -device sb16 \
  -vga vmware \
  -display vnc=:0 \
  -rtc base=localtime \
  -boot order=c
```

Connect via VNC client to `localhost:5900`.

### 8.2 Verification Checklist

| Check | How | Expected |
|-------|-----|----------|
| Windows boots | VNC shows desktop | Start menu, taskbar visible |
| Display resolution | Right-click Desktop → Properties → Settings | 1024×768 @ 16-bit |
| Display driver | Device Manager → Display adapters | VMware SVGA II |
| Network driver | Device Manager → Network adapters | Realtek RTL8029(AS) |
| Network IP | Start → Run → `winipcfg` | Shows adapter with IP |
| Audio driver | Device Manager → Sound | Creative SB16 |
| Audio playback | Open `C:\Windows\Media\tada.wav` | Sound plays |
| Lego Loco launch | Double-click desktop icon | Game starts, menu renders |
| Clean shutdown | Start → Shut Down | Powers off without errors |

### 8.3 TAP/Bridge Test (Production-Like)

For a more realistic test matching the container networking:

```bash
# Create bridge and TAP (requires root)
sudo ip link add name loco-br type bridge
sudo ip addr add 192.168.10.1/24 dev loco-br
sudo ip link set loco-br up
sudo ip tuntap add tap0 mode tap
sudo ip link set tap0 master loco-br
sudo ip link set tap0 up

# Boot with TAP networking
qemu-system-i386 \
  -M pc -cpu pentium2 \
  -m 512 \
  -hda win98.qcow2 \
  -net nic,model=ne2k_pci \
  -net tap,ifname=tap0,script=no,downscript=no \
  -device sb16,audiodev=snd0 \
  -audiodev pa,id=snd0 \
  -vga vmware \
  -display vnc=0.0.0.0:1 \
  -rtc base=localtime \
  -boot order=c
```

Verify: `ping 192.168.10.1` from within the Win98 guest reaches the bridge.

---

## 9. Phase 8 — Snapshot Creation & Registry Push

### 9.1 Create COW Snapshot

For production deployment, the base image is never modified directly. A copy-on-write (COW) snapshot is created on top:

```bash
qemu-img create -f qcow2 -b win98.qcow2 -F qcow2 snapshot.qcow2
```

This allows each container instance to have its own writable layer without modifying the base.

### 9.2 Automated Snapshot Building

Use the project's build script:

```bash
./scripts/create_win98_image.sh \
  --disk-image /path/to/disk_image.vhd \
  --build-snapshots \
  --registry ghcr.io/mroie \
  --tag v$(date +%Y%m%d)
```

This produces three snapshot variants:
- `win98-base` — Clean Win98 + drivers + Lego Loco
- `win98-games` — Extended with additional software
- `win98-productivity` — Office/productivity tools

### 9.3 Advanced Snapshot Builder (Python)

For more control, use the Python snapshot builder:

```bash
python3 scripts/snapshot_builder.py /path/to/win98.qcow2 ghcr.io/mroie/qemu-snapshots win98-base
```

This script:
1. Creates a COW overlay from the base image.
2. Boots QEMU with a monitor socket for automation.
3. Waits for Win98 to boot (configurable timeout).
4. Can install software via monitor commands and ISO mounting.
5. Shuts down the VM cleanly.
6. Converts the working snapshot to a standalone qcow2.
7. Packages it into a container image and pushes to the registry.

### 9.4 Push to Container Registry

Snapshots are stored as OCI artifacts in the container registry:

```
ghcr.io/mroie/qemu-snapshots:win98-base
ghcr.io/mroie/qemu-snapshots:win98-games
ghcr.io/mroie/qemu-snapshots:win98-productivity
```

The `qemu-softgpu` Dockerfile pulls the base image from:
```
ghcr.io/mroie/lego-loco-cluster/win98-softgpu:latest
```

---

## 10. Phase 9 — Container Integration

### 10.1 How the Image is Used in Containers

**qemu-softgpu container** (production path — see [containers/qemu-softgpu/Dockerfile](../../../containers/qemu-softgpu/Dockerfile)):

1. Multi-stage build pulls `win98-softgpu:latest` → extracts `win98.qcow2.builtin`.
2. Stores at `/opt/builtin-images/win98.qcow2.builtin` inside the container.
3. At runtime, `entrypoint.sh` either:
   - Downloads a pre-built snapshot from registry (if `USE_PREBUILT_SNAPSHOT=true`), or
   - Creates a COW snapshot from the builtin image at `/tmp/win98_<timestamp>.qcow2`.
4. Launches QEMU with the snapshot.

**qemu-bootable container** (alternative path — see [containers/qemu-bootable/Dockerfile](../../../containers/qemu-bootable/Dockerfile)):

1. Expects the image to be volume-mounted at `/images/`.
2. Launches QEMU directly with VNC + x11vnc on port 5901.

### 10.2 Deploy with Docker

```bash
docker run --rm --network host --cap-add=NET_ADMIN \
  -e TAP_IF=tap0 -e BRIDGE=loco-br \
  -v /path/to/win98.qcow2:/images/win98.qcow2 \
  ghcr.io/mroie/qemu-loco:latest
```

### 10.3 Deploy with Helm

```bash
helm install loco helm/loco-chart/ \
  --set emulator.usePrebuiltSnapshot=true \
  --set emulator.snapshotTag=win98-base
```

---

## 11. Troubleshooting

### Common Issues

| Problem | Cause | Solution |
|---------|-------|----------|
| **SoftGPU doesn't initialize** | Driver not installed correctly or conflicts with Voodoo 3D remnants | Reboot twice. If still failing, uninstall Voodoo 3D first in Device Manager, then install SoftGPU. Fall back to VESA VBE if necessary. |
| **qemu-img convert fails with "unknown format"** | Wrong `-f` flag for source format | Run `qemu-img info <source>` first to identify the actual format. PCem VHD = `vpc`, not `vhd`. |
| **Win98 shows "Disk is not formatted"** | Used NTFS instead of FAT32 | Re-partition with FDISK using "Large Disk Support = Yes" for FAT32. |
| **No network adapter in Device Manager** | RTL8029 driver not installed | Manually install via Add New Hardware wizard; driver does not auto-detect. |
| **DMA/IRQ conflict on SB16** | Resource conflict with another device | Device Manager → SB16 → Properties → Resources → manually set IRQ 5, DMA 1/5. |
| **Lego Loco autorun doesn't trigger** | Win98 autorun disabled or CD not mounted correctly | Run `D:\SETUP.EXE` manually. |
| **QEMU boot shows black screen** | Missing `-vga vmware` or wrong boot order | Ensure `-vga vmware` and `-boot order=c`. Check `qemu-img info` confirms valid image. |
| **Container init fails: "Built-in disk image not found"** | Stale `latest` tag cached by Minikube/Kind | Use unique image tags (`v<timestamp>`) instead of `latest`. See [LESSONS_LEARNED_WIN98_ISO.md](../../LESSONS_LEARNED_WIN98_ISO.md). |
| **Snapshot download fails in container** | No `skopeo` or `crane` in image, or registry auth missing | Ensure the container image includes `skopeo`. For private registries, configure `imagePullSecrets` in Helm. |
| **Display stuck at 800×600** | VESA VBE fallback active instead of SoftGPU | Reinstall SoftGPU. Device Manager → Display adapters should show VMware SVGA II, not Standard VGA. |
| **Multiple reboots needed after driver install** | Normal for Win98 — Plug & Play re-detection | Allow 2–3 reboots after each driver install before troubleshooting further. |

### Diagnostic Commands

**Inside Win98 guest**:
```
winipcfg              — Check network adapter and IP
ping 192.168.10.1     — Test bridge connectivity
msinfo32              — Full system info (if installed)
```

**On host**:
```bash
qemu-img info <image>           — Check image format and size
qemu-img check <image>          — Verify image integrity
docker inspect <container>      — Check container config
kubectl logs <pod> -c init-disk-image  — Debug init container
```

---

## 12. Quick Reference — Full Pipeline Commands

```bash
# 1. Convert PCem disk image
./scripts/create_win98_image.sh --disk-image ~/pcem/LOCO-NODE.vhd --output-dir ./images

# 2. Verify conversion
qemu-img info ./images/win98.qcow2
qemu-img check ./images/win98.qcow2

# 3. Quick QEMU smoke test
qemu-system-i386 -M pc -cpu pentium2 -m 512 -hda ./images/win98.qcow2 \
  -device ne2k_pci,netdev=net0 -netdev user,id=net0 \
  -device sb16 -vga vmware -display vnc=:0 -rtc base=localtime

# 4. Build container image with snapshots
./scripts/create_win98_image.sh \
  --disk-image ./images/win98.qcow2 \
  --build-snapshots \
  --tag v$(date +%Y%m%d) \
  --no-push   # remove --no-push for registry upload

# 5. Run in container
docker run --rm --network host --cap-add=NET_ADMIN \
  -v ./images/win98.qcow2:/images/win98.qcow2 \
  ghcr.io/mroie/qemu-loco:v$(date +%Y%m%d)
```

---

## 13. Related Documentation

- [image-creation-checklist.md](image-creation-checklist.md) — Condensed checklist version
- [known-driver-issues.md](known-driver-issues.md) — Driver-specific troubleshooting
- [game-navigation-map.md](game-navigation-map.md) — Lego Loco menu tree and multiplayer flow
- [LESSONS_LEARNED_WIN98_ISO.md](../../LESSONS_LEARNED_WIN98_ISO.md) — Minikube caching & tagging pitfalls
- [STORAGE_STRATEGY.md](../../STORAGE_STRATEGY.md) — Storage modes (persistent, hybrid, ephemeral)
- [SNAPSHOT_IMPLEMENTATION.md](../../SNAPSHOT_IMPLEMENTATION.md) — Snapshot architecture and CI/CD integration
- [config/qemu.json](../../../config/qemu.json) — Target QEMU hardware configuration
