# PCem / 86Box Runtime Evaluation

Date: 2026-05-15

## Context

The live cluster currently runs Windows 98 through QEMU with SoftGPU on the
VMware SVGA adapter. Guest LAN now works through a per-pod Linux bridge, TAP
interface, VXLAN mesh, and a tiny DHCP server. The blocking issue is frame rate:
without KVM, QEMU TCG pins one host thread and Lego Loco barely survives the
intro / DirectDraw path.

PCem and 86Box solve a different problem from QEMU. They emulate period PC
hardware directly, including late-1990s chipsets, Voodoo cards, SB/Ensoniq
audio, and NE2000/Realtek NICs. Their fast path is dynamic recompilation plus
emulated accelerator-specific render paths, not host virtualization through
`/dev/kvm`.

## Source Findings

- 86Box is current and publishes Linux AppImage builds. Latest stable checked:
  v5.3, released 2025-12-22.
  Source: https://86box.net/
- 86Box performance is mostly single-threaded for machine emulation, so host
  IPC matters. Its docs explicitly warn that most emulation logic runs in a
  single thread.
  Source: https://86box.net/
- 86Box dynamic recompiler is available for 486-class CPUs and mandatory for
  Pentium-class CPUs. This is the main CPU-side difference from QEMU TCG for
  this use case.
  Source: https://86box.readthedocs.io/en/stable/settings/machine.html
- 86Box Voodoo 1/2 and Voodoo3/Banshee configuration supports render threads
  and a Voodoo dynamic recompiler. That is the likely reason Voodoo-based Win98
  setups can look much smoother than our current SoftGPU-on-QEMU-TCG path.
  Source: https://86box.readthedocs.io/en/latest/settings/display.html
- 86Box supports TAP networking on Linux. The configured bridge name represents
  the virtual network; all apps using the same bridge are on the same network.
  Source: https://86box.readthedocs.io/en/stable/hardware/network.html
- PCem v17 exists, but the latest upstream release is from 2022. Its source
  supports optional networking and PCap networking at build time, and the README
  describes Voodoo software emulation with a dynamic recompiler.
  Source: https://github.com/sarah-walker-pcem/pcem
- SoftGPU is still useful for QEMU/VMware-SVGA style guests, but upstream
  support notes show QEMU `vmware` is not the strongest path for all 3D modes;
  `std + qemu-3dfx` has broader acceleration support in the SoftGPU matrix.
  Source: https://github.com/JHRobotics/softgpu

## Local Repo Findings

- `containers/pcem` is a placeholder. Its Dockerfile installs `pcem` from
  Ubuntu 22.04 apt, but the default Ubuntu 22.04 package index checked here has
  no `pcem` or `86box` package candidate.
- The PCem entrypoint assumes a pre-existing X display, runs `pcem --config
  /pcem.cfg --hda ...`, and sends a GStreamer WebRTC pipeline to `fakesink`.
  It is not integrated with the backend RTP path, health checks, identity
  injection, the StatefulSet, or the proven VXLAN guest LAN logic.
- Existing local documentation already points to the right hardware class:
  GA-686BX, Pentium II, RTL8029AS, SB/Ensoniq audio, and Voodoo/Voodoo3.

## Backend Decision

Primary path remains QEMU + SoftGPU + KVM:

- It already has pod identity, persistent snapshots, VNC capture, RTP streaming,
  QMP control, the guest L2 mesh, and DHCP.
- Enabling VT-x and exposing `/dev/kvm` should remove the dominant bottleneck.
- This is the best scalable/cloud-native path because KVM is a normal Linux
  virtualization primitive.

Secondary experiment should be 86Box, not PCem:

- 86Box is maintained and has current Linux release artifacts.
- It has first-class TAP mode on Linux, so it can attach to the same `loco-br`
  bridge used by the current VXLAN mesh.
- It has the performance features relevant to our symptoms: Pentium dynarec,
  Voodoo render threads, and Voodoo recompiler.

PCem should stay as an image-building/reference backend unless a specific PCem
compatibility win appears. It is less practical for Kubernetes runtime because
we would have to build it ourselves, then still solve Xvfb, streaming, control,
and network integration.

## 86Box Runtime Shape

The minimum viable 86Box pod would reuse the QEMU network setup up to the bridge
creation step, then let 86Box allocate its own TAP interface and attach it to
the bridge.

Required pod/container capabilities:

- `/dev/net/tun`
- `NET_ADMIN`
- `NET_RAW` if running non-root with file capabilities, or privileged for the
  first proof of concept
- Xvfb or another X server
- PulseAudio or PipeWire/PulseAudio compatibility
- x11vnc or `ximagesrc`-based capture

Candidate `86box.cfg` network section:

```ini
[Network]
net_01_card = ne2kpci
net_01_net_type = tap
net_01_host_device = loco-br
net_01_link = 0

[Realtek RTL8029AS #1]
mac = 10:00:00
```

For ordinal 0, `mac = 10:00:00` yields full Realtek-style MAC
`00:e0:4c:10:00:00`; the current mini DHCP server only depends on the last MAC
byte, so it will hand out `192.168.10.10`. Ordinal 1 should use `10:00:01`,
giving `192.168.10.11`.

Candidate machine/video core:

```ini
[General]
confirm_exit = 0
confirm_reset = 0
vid_renderer = qt_software
force_43 = 1

[Machine]
machine = 686bx
cpu_family = pentium2_deschutes
cpu_speed = 300000000
cpu_multi = 4.5
cpu_use_dynarec = 1
fpu_type = internal
mem_size = 524288
time_sync = local

[Video]
gfxcard = voodoo3_3k_pci

[3dfx Voodoo3 3000]
render_threads = 2
recompiler = 1
bilinear = 0
dithersub = 0
dacfilter = 0
```

The existing QEMU SoftGPU disk is not a clean drop-in runtime disk for this.
It currently expects VMware SVGA II. A real benchmark needs either:

1. A fresh Win98 image built under 86Box with Voodoo3 and RTL8029 drivers, or
2. The current image reverted to Standard VGA, then booted under 86Box to install
   Voodoo3 drivers.

## Benchmark Gate

Do not port the whole Helm release to 86Box until a single instance passes these
checks:

1. Boot Win98 to desktop under 86Box in a container.
2. Confirm Voodoo3 driver active at the target game resolution.
3. Launch Lego Loco and pass the intro / main-menu path that stalls under QEMU
   TCG.
4. Confirm DHCP lease and pod-to-guest ping on `192.168.10.10`.
5. Measure host CPU, emulated speed stability, and frame progression for at
   least 5 minutes.

If that succeeds, the 86Box backend should become a selectable experimental
emulator mode. If it fails, the effort should return to QEMU + KVM and possibly
QEMU `std + qemu-3dfx` rather than continuing with PCem.
