# PCem emulator container

Runs **Windows 98 SE + LEGO LOCO** on emulated period hardware — a FIC VA-503+
(Super Socket 7 / VIA MVP3) with a Pentium MMX 200 and a 3dfx Voodoo3 3000 —
and publishes it to the cluster as **raw RFB on :5901** plus **HTTP health on
:8080**, which is the same contract the QEMU emulator exposes. The backend's
WebSocket→TCP bridge and the frontend instance grid therefore pick it up with
no changes on their side.

```
Xvnc :99 (RFB-native X server)  →  PCem SDL window
        ↓ :5901
backend /proxy/vnc/<id>  (WebSocket ⇄ TCP bridge)  →  noVNC in the frontend grid
```

This container is the productionised form of the bring-up log in
[`standalone/README.md`](standalone/README.md); gotcha numbers in the source
comments refer to that file. Read it before changing anything here — most of
what looks arbitrary below is a fix for something that cost a session.

## Quick start (plain Docker)

```sh
docker build -t loco-pcem:dev containers/pcem
mkdir -p /tmp/pcem-images

docker run -d --name pcem -p 5901:5901 -p 8080:8080 \
  -v /tmp/pcem-images:/images --cpus 2 --memory 2g loco-pcem:dev

curl -s localhost:8080/health | jq        # ready:true once the desktop is up
python3 scripts/vnc-screenshot.py localhost:5901 shot.png
```

On first start the entrypoint pulls the ~500 MB disk snapshot from GHCR with
plain `curl` (no skopeo/crane needed — see `scripts/pull-snapshot.sh`). Cold
boot to a usable Windows 98 desktop is roughly **75 seconds** after that.

## In the cluster

```sh
helm upgrade --install loco helm/loco-chart -n loco --create-namespace \
  -f helm/loco-chart/values-pcem.yaml
```

`emulator.flavor: pcem` switches the StatefulSet over. The only structural
difference from the QEMU flavor is that PCem skips the qcow2-shaped
`init-disk-image` init container and resolves its own disk. See
[`values-pcem.yaml`](../../helm/loco-chart/values-pcem.yaml) for the knobs.

**Each pod needs its own disk.** PCem writes through to the image, so the
values file uses a per-pod `emptyDir` rather than a shared PVC — pointing two
instances at one file corrupts it. `emulator.snapshotCache` turns "every pod
pulls 500 MB" into "one pull per node".

## Configuration

| Variable | Default | Notes |
|---|---|---|
| `PCEM_MODEL` | `fic_va503p` | **Must match the board the disk was installed on.** |
| `PCEM_GFXCARD` | `v3_3000` | Voodoo3 3000 |
| `PCEM_MEM_SIZE` | `65536` | KB |
| `PCEM_MOUSE_TYPE` | `0` | **Must match the guest's bound driver.** The snapshot uses a serial mouse; PS/2 leaves the cursor frozen with no error. |
| `PCEM_FLOPPY_A_TYPE` | `5` | 3.5" 1.44M — see "Unattended boot" |
| `PCEM_VNC_MOUSE` | `1` | remote-pointer patch; 0 = upstream click-to-grab behaviour |
| `PCEM_POINTER_MODE` | `absolute` | `absolute` = guest cursor goes where the client points; `relative` = nudge by motion |
| `PCEM_MOUSE_SPEED` | `1` | guest pointer ballistics; `0` if acceleration is disabled in the guest |
| `PCEM_MOUSE_CREEP` | `2` | largest packet the guest moves 1:1 — **measured**, not the documented `MouseThreshold1` of 6 |
| `PCEM_MOUSE_DOUBLE_MIN` | `8` | smallest packet the guest is known to double; packets between the two are never emitted |
| `PCEM_MOUSE_MAX_PACKET` | `120` | `mouse_serial_poll()` clamps at 127 |
| `GUEST_MOUSE_ACCEL` | `0` | 0 writes `MouseSpeed=0` into the guest registry, so a mickey is a pixel |
| `PCEM_VID_RESIZE` | `2` | 2 pins the window to `SCREEN_*` and stretches the guest to fill it — no black bars |
| `PCEM_FULLSCREEN_SCALE` | `0` | 0 stretch, 1 = 4:3, 2 = square pixels, 3 = integer multiples |
| `GUEST_RESOLUTION` | *(unset)* | e.g. `640,480` — Windows desktop resolution, applied from the next boot |
| `PCEM_NETCARD` | `none` | `ne2000` or `rtl8029as` |
| `PCEM_NET_MODE` | `none` | `direct` (bridge onto an interface) or `vxlan` (bridge+tap meshed to peer pods) |
| `PCEM_MAC` | derived | must be unique per instance; defaults to `52:54:00:10:c0:<ordinal>` |
| `SNAPSHOT_IMAGE` | `…:pcem-win98-loco-1024x768` | OCI image holding the disk |
| `SNAPSHOT_CACHE_DIR` | *(unset)* | node-local cache directory |
| `DISK_DIR` / `DISK_NAME` | `/images` / `win98-loco.vhd` | |
| `SCREEN_WIDTH` / `SCREEN_HEIGHT` | `1024` / `768` | VNC framebuffer size; the guest is scaled to fill it |
| `PCEM_DEBUG_LOG` | `0` | 1 keeps PCem's very chatty debug log |
| `VNC_BACKEND` | `xvnc` | `xvnc` = TigerVNC (RFB-native X server); `x11vnc` = Xvfb + screen grabber |

## Things that will bite you

**The board must match the disk.** Windows binds chipset drivers at install
time. Booting the shipped snapshot on `430vx` instead of `fic_va503p` comes up
in a PnP re-detect storm: VGA fallback at 640×480, no mouse, and a "New
Hardware Found" wizard demanding the Windows 98 SE CD. Both BIOS ROMs ship in
the image so either board is available, but the default is the right one.

**It has to be the debug build.** `--enable-release-build` (-O3 plus
`-DRELEASE_BUILD`) miscompiles the IDE disk-detection path and every boot ends
in *"Primary master hard disk fail"* (gotcha #9). The `-O0` build still holds
100–101% of real Pentium-MMX-200 speed, because the hot path is
dynarec-generated code rather than compiler output. Do not "optimise" this.

**Unattended boot depends on CMOS.** With no NVRAM for the configured board the
Award BIOS POSTs with *"CMOS checksum error – Defaults loaded"* and halts on
*"Press F1 to continue"* — forever, on a headless pod. Two things prevent that:
a known-good CMOS is seeded from `nvr-seed/` on first start, and NVRAM is kept
on the disk volume so it survives restarts. A mismatched floppy type causes the
same halt via *"Floppy disk(s) fail (40)"*, which is why `PCEM_FLOPPY_A_TYPE`
defaults to a 1.44M drive rather than "none". If CMOS cannot be seeded (an
unknown `PCEM_MODEL`), the entrypoint falls back to blind-pressing F1 through
POST.

**PCem is single-threaded and has no KVM path.** Budget ~1 core per instance
and scale replicas against cores. With the default `xvnc` backend the VNC
server itself costs ~2% of a core; on `x11vnc` it costs close to a whole one.

**The VNC server is TigerVNC's `Xvnc`, not `x11vnc`** (`VNC_BACKEND=xvnc`,
the default). Xvnc *is* an X server with RFB built in: PCem draws into it and
clients read the same framebuffer, so nothing scrapes the screen.

`VNC_BACKEND=x11vnc` restores the Xvfb + screen-grabber arrangement that
`containers/qemu-softgpu` uses. Avoid it here. Scraping an emulator that
repaints continuously costs x11vnc ~95% of a core per instance, and in
Kubernetes it also breaks the handshake outright: the client's TCP connection
establishes, the RFB version banner never arrives, and the tile in the browser
sits "connected" and permanently black while `/proc/net/tcp` still shows a
healthy LISTEN socket. (libvncserver's WebSocket sniff aborts the client
instead of falling through to plain RFB.) The same image behaves under plain
Docker, which is what makes it such an unpleasant thing to chase.

**Never probe the VNC port by connecting to it.** x11vnc runs WebSocket
sniffing against every inbound connection, and a prober that dials and hangs
up every few seconds eventually stops it answering new connections — the check
causes the outage it is meant to detect (`webSocketsHandshake: unknown
connection error` in `x11vnc.log` is the tell). `health-server.py` reads
`/proc/net/tcp` for a LISTEN socket instead. `backend/services/probingService.js`
carries a comment about removing the same probe for the same reason.

**The health endpoint must answer fast.** The backend gives each probe 2000 ms
and marks the instance `degraded` on timeout, which drops its tile out of the
frontend grid entirely. State is sampled on a background thread so requests
never block on an X server call.

**It only flushes the disk on a clean exit,** and it ignores plain SIGTERM
(gotcha #12). The entrypoint's shutdown handler sends `WM_DELETE_WINDOW` to the
wx frame, which is the one path that runs PCem's close handler. Killing a pod
with a short `terminationGracePeriodSeconds` will lose guest writes.

**A fresh `$HOME` used to segfault it.** `paths_onconfigloaded()` calls
`pclog()` before anything creates `$HOME/.pcem/logs`, `pclog`'s `fopen()`
returns NULL, and it `fputs()` to it unchecked — the crash lands inside glibc
and reads like a missing shared library. The entrypoint pre-creates every
directory PCem expects.

## Direct (absolute) pointing

VNC, RDP and touch/tablet devices all report **where the pointer is**. A PS/2 or
serial mouse can only report **how far it moved**. `PCEM_POINTER_MODE=absolute`
reconciles the two so the guest cursor lands exactly where the client points —
no drift, no "chase the cursor", and clicks hit what they are aimed at.

There is no absolute pointing device to emulate (no USB, and Windows 98 has no
tablet driver), so the patch keeps a model of where the guest cursor is and
emits the mouse packet that closes the gap:

- **Homing.** The guest cursor's real position is unknowable at startup, so it
  is driven hard into the top-left corner, where it clamps regardless of any
  acceleration setting. That makes the model true. A guest video-mode change
  re-homes automatically.
- **Scaling.** With `vid_resize=2` (see *Filling the view* below) the window and
  the guest picture are different sizes, so the client position is mapped
  through `pcem_guest_size()` — which reads `blit_rect`, the framebuffer PCem
  actually scales. Do not use `winsizex`/`winsizey` for this: they track the
  window, and under `vid_resize=2` they keep their 640x480 initialiser forever.
- **Ballistics — and why this is still not solved.** The guest doubles a packet
  above some size (measured: 2 mickeys moves 2 px, 5 moves 10), so the model
  never emits inside the uncertain band between `PCEM_MOUSE_CREEP` (2, known
  1:1) and `PCEM_MOUSE_DOUBLE_MIN` (8, known to double). Distance is covered by
  emitting `want/2` and letting the guest double it; only the last few pixels
  creep.

  That is exact on the desktop and **wrong inside the game**, and the reason is
  now known: LEGO LOCO calls `SystemParametersInfo(SPI_SETMOUSE)` at startup and
  installs its *own* acceleration curve. It has no DirectInput import at all —
  it drives the Windows system cursor through `GetCursorPos`/`SetCursorPos`. So
  the model is open loop against a transfer function that changes when the game
  launches, which is also why writing `Control Panel\Mouse` never helped: LOCO
  overwrites the live values afterwards.

  No choice of constants can be right in both regimes. See *Making the pointer
  real-time* below.

- **Edge re-sync.** Parking the client pointer against a screen edge pushes the
  guest cursor into the same edge, which re-establishes the model exactly. Any
  drift is one corner-flick away from being corrected.

`GUEST_MOUSE_ACCEL=0` (the default) additionally writes `MouseSpeed=0` into the
guest's `Control Panel\Mouse` via `LOCOID.REG`. If you confirm it has taken
effect, `PCEM_MOUSE_SPEED=0` then removes the cap and the mapping becomes a
straight 1:1. Keep the two in agreement — claiming acceleration is off while it
is on makes the model predict half the travel.

To re-measure the threshold on a different image: park the pointer at 0,0, ask
for a mid-screen position, screenshot, and compare where the guest cursor
actually landed. `scripts/vnc-drive.py <host:port> move 0 0 sleep 3 shot a.png
move 256 192 sleep 3 shot b.png` and diffing the two frames isolates the cursor.

`PCEM_VNC_MOUSE_DEBUG=1` traces every poll — absolute position, window rect,
target, model and emitted packet — which is the only way to tell "the client's
input never arrived" apart from "the guest has no driver bound to this mouse".

## Making the pointer real-time

RESOLVED for the current stack — measured, not asserted. With the three pieces
in agreement (PS/2 `mouse_type = 2`; `MouseSpeed=0` delivered into the guest
registry by `LOCOID.REG`; `PCEM_MOUSE_SPEED=0` so the model assumes the 1:1
curve those two produce) and the guest at native 1024x768
(`GUEST_RESOLUTION=1024,768`, making the pointer mapping the identity),
template-matched cursor tracking (`scripts/cursor-locate.py`) measures:

* menu: pixel-perfect (match score 0.0000), zero drift over a closed path
* in-world: gain 1.000/1.000 at every probe, constant sub-4px offset
* the true screen corners reachable — the original complaint
* clicks land where aimed (1.0s hold; LOCO ignores short clicks)

An earlier conclusion that "the registry values did not take" was wrong: the
values were live in the hive all along, and the measurements that condemned
them were frame-diffs poisoned by LOCO's animated menu. Measure cursors by
matching the sprite, never by diffing frames.

The guest-agent design below is kept because it is the answer if a *future*
game or driver reinstates a curve the model cannot assume away — it closes the
loop with `GetCursorPos()` as the oracle. It is not currently needed.

The measured facts it rests on:

**Measured latency budget** — four comparable serial quanta, no single villain:

| Hop | Cost |
|---|---|
| noVNC's mouse throttle (`MOUSE_MOVE_DELAY = 17`, coalescing) | 8–25 ms; the VR path already bypasses it |
| Backend WS↔TCP bridge | <1 ms, no coalescing (but Nagle is on toward Xvnc — one line to fix) |
| **PCem's mouse sampling clock** | **20.0 ms** — `pollmouse_delay = 2` gating a 100 Hz loop |
| Xvnc frame clock (`FrameRate` 60) | 16.7–33.3 ms, bimodal because it beats against the 50 Hz cursor clock |
| Browser compositor | 3–20 ms |

The 20 ms sampling clock is the throughput limit — measured at **49.9 Hz** on
both live pods, three independent ways. Creep mode's ~100 px/s is exactly
2 px × 49.9. The UART is *not* a limit: PCem does not emulate 1200 baud (the
divisor is stored and used for timing nowhere), and the serial FIFO drains
333 packets/s against an offered 50.

**Four facts that kill the obvious designs:**

1. The Voodoo3 hardware-cursor register is not a position oracle on this image —
   `SYSTEM.INI` has `display.drv=pnpdrvr.drv` (Standard PCI Graphics Adapter),
   no 3dfx driver, so `hwcursor.ena` is permanently 0 and the cursor is software
   painted into VRAM. That also means there is no sprite to hide or export.
2. LEGO LOCO has **no DirectInput import**. It uses `GetCursorPos`,
   `SetCursorPos`, `SetCapture`, `SystemParametersInfoA`. The in-game difference
   is not DirectInput bypassing acceleration — it is LOCO installing its own
   curve with `SPI_SETMOUSE`, which is also why the registry campaign failed.
3. Framebuffer template-matching the cursor is hopeless against LOCO's moving
   trains and water.
4. There is no better device to switch to: it is already PS/2, gameport is
   ~20 Hz, and PCem v17 has no USB.

**The design.** Put an absolute pointer *inside* the guest, where the ballistics
do not exist, and let it report back — closing the loop that has been open all
along:

- A **mailbox device in PCem** (new source file, I/O ports + a seqlock struct in
  shared memory). The host writes the target in guest pixels; the guest writes
  back what it observes.
- A **~200-line Win32 agent** in the guest that polls the mailbox, calls
  `mouse_event(MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE)` — which applies no
  ballistics at all — then calls `GetCursorPos()` and writes the result back.

`GetCursorPos()` is the oracle `hwCurLoc` was supposed to be: it works on this
image, it returns the hotspot (so no hotspot calibration), and it sees the truth
*inside LOCO*, because LOCO uses the system cursor.

Because the guest polls the mailbox, this also steps around the 20 ms host
sampling clock entirely.

The relative model in `patches/vnc-mouse.py` is demoted to a fallback: if the
agent's heartbeat goes stale it takes over, restricted to sub-threshold packets —
exact by construction, slower. Never fast-but-wrong.

## Filling the view

PCem sizes its SDL window to the guest's video mode, so an 800x600 Windows
desktop sits in the corner of the 1024x768 VNC framebuffer and the browser tile
shows black bars — which move every time the guest changes mode.

`PCEM_VID_RESIZE=2` (the default) is PCem's "custom resolution": the window is
pinned to `custom_width`/`custom_height` (i.e. `SCREEN_WIDTH`/`SCREEN_HEIGHT`)
and `win_doresize` is ignored, so a guest mode change no longer resizes it.
`sdl_renderer_present()` already scales the guest framebuffer to the window via
`sdl_scale(video_fullscreen_scale, ...)`, so the picture stretches to fill.
`PCEM_FULLSCREEN_SCALE` picks the mode: 0 = stretch, 1 = 4:3, 2 = square pixels,
3 = integer multiples.

The `[SDL2] fullscreen` config key is deliberately **not** used. At startup it
only ticks the menu checkbox — the SDL fullscreen switch itself lives in the
menu handler (`wx-sdl2.c`) and never runs headless.

That fills the framebuffer with the *desktop*. Filling it with the *game* is a
separate question: LEGO LOCO plays in a fixed-size window, so on a roomier
desktop it is a window with the world scrolling inside it. `GUEST_RESOLUTION`
("640,480") writes the desktop resolution into `LOCOID.REG` so the desktop can
be matched to the game. Like the computer name it is imported at logon, so it
governs from the *next* boot onwards.

## Guest LAN

LEGO LOCO multiplayer is DirectPlay over TCP/IP, which needs both guests on one
layer-2 segment. PCem's default SLiRP backend is a userspace NAT stack — every
instance is its own island on 10.0.2.15 — so it cannot carry a LAN game.

`patches/linux-pcap.py` enables PCem's **PCap backend on Linux**. Upstream
compiles it `#ifdef _WIN32` only and hard-codes `net_is_slirp = 1` everywhere
else; the code is already there and already used on Windows, it just was not
being built. With it, `PCEM_NETCARD=ne2000` + `PCEM_NET_MODE=direct|vxlan` puts
the guest's frames onto a real interface:

```
ne2000 init	slirp is 0 net_is_pcap is 1
ne2000 Pcap version [libpcap version 1.10.3 (with TPACKET_V3)]
ne2000 Using filter	[( ((ether dst ff:ff:ff:ff:ff:ff) or (ether dst 52:54:00:10:c0:00)) and not (ether src 52:54:00:10:c0:00) )]
```

`net_type` and `pcap_device` live in PCem's **global** config
(`$HOME/.pcem/pcem.cfg`), not the machine config passed to `--config`. Getting
that wrong is silent — ne2000 just falls back to SLiRP.

Each instance needs a distinct `macaddr`; the entrypoint derives one from the
StatefulSet ordinal. `vxlan` mode builds the same bridge + tap + VXLAN mesh the
QEMU flavor uses, because Kubernetes joins pods at L3 and foreign MACs do not
cross the CNI.

## The VNC mouse patch

Upstream PCem is built for someone sitting at the machine: the first left-click
grabs the pointer and switches SDL to relative mode, which warps the host
pointer back to the window centre every frame. A VNC client sends *absolute*
positions, so upstream's warping fights every one of them — this is the "mouse
clicks routinely fail to register" symptom recorded as gotcha #23.

`patches/vnc-mouse.py` adds a `PCEM_VNC_MOUSE=1` mode that never grabs, derives
guest motion from frame-to-frame deltas of the absolute pointer, and stops
right-click from opening PCem's own menu over the guest. The patch asserts on
its anchors, so it fails the build rather than silently not applying if PCem's
source shape ever changes. Set `PCEM_VNC_MOUSE=0` for stock behaviour.

Because the guest applies its own pointer acceleration, the two cursors can
drift apart; moving to a screen corner re-synchronises them.

## Getting Windows onto the LAN

The shipped snapshot was installed without a NIC, and the Windows 98 install
source is not on the disk (`C:\WINDOWS\OPTIONS\CABS` does not exist — the only
cabs are registry backups), so adding a network card asks for the retail CD.

It does not need the CD. Everything required is already in this repo's own
QEMU golden image, which *is* network-configured:

1. **The card.** Use `PCEM_NETCARD=rtl8029as`, not `ne2000`. The Realtek is a
   PCI card, so Windows PnP finds it at boot; NE2000 is ISA at 0x300/IRQ 10 and
   has to be added by hand through Add New Hardware.
2. **The driver.** `NETRT.INF` — which binds `PCI\VEN_10EC&DEV_8029` to
   `rtl8029.sys` — is *already* on the PCem disk. Only the binary is missing.
   Lift it out of the QEMU snapshot:

   ```sh
   docker create --name x ghcr.io/mroie/lego-loco-cluster/emulator-snapshot:netready /bin/true
   docker cp x:/emulator-snapshot/netready.qcow2 .
   qemu-img convert -f qcow2 -O raw netready.qcow2 raw.img
   dd if=raw.img of=part.img bs=512 skip=63          # partition starts at LBA 63
   MTOOLS_SKIP_CHECK=1 mcopy -i part.img ::/WINDOWS/SYSTEM/RTL8029.SYS .
   ```
3. **The rest of the network stack.** Installing a NIC also pulls in Client for
   Microsoft Networks and the TCP/IP transport, which is another ~50 files.
   Derive the exact list from the INFs rather than guessing — grepping
   `NETRT.INF NETCLI*.INF NETTRANS.INF NETSERV*.INF NETDEF.INF NETSNMP.INF`
   for `*.dll|vxd|386|sys|exe` gives ~53 files totalling 2.4 MB. (Grepping
   *all* `NET*.INF` gives 88 MB — every NIC vendor's driver.)
4. **Stage them on C:.** The guest disk has only ~21 MB free, which is why this
   goes in `C:\DRIVERS\` rather than as a CD image. When the installer asks
   for the Windows 98 CD, click OK and type `C:\DRIVERS` into "Copy files
   from".

**Reading and writing the guest filesystem from the host** needs two things
that are easy to miss: `MTOOLS_SKIP_CHECK=1` (mtools otherwise refuses this
disk with "Big disks not supported on this architecture"), and working on the
*partition*, not the VHD — `dd bs=512 skip=63` out, edit, `dd seek=63
conv=notrunc` back.

**Do not leave a network install half-finished.** If the file copy is
cancelled, Windows has already written the VxDs into SYSTEM.INI and the next
boot stops on "Cannot find a device file ... vredir.vxd". Start again from a
clean copy of the disk rather than trying to repair it.

Guest addressing is DHCP, served by `scripts/mini-dhcp.py` on instance 0 (the
same server the QEMU flavor uses). The lease follows the MAC —
`192.168.10.(10 + last byte)` — so one golden disk can be cloned to N
instances and each still gets a distinct, stable address with nothing
configured per-instance inside Windows.

## Known gaps

**Guest NetBIOS names collide.** Every guest reports the same Windows name
(`W5C5G7` in the DHCP log), because the `LOCOID.REG` import does not appear to
take effect. The file and its StartUp `.BAT` are both verifiably written to the
right paths on the disk, and `regedit /s` should apply them at logon — but
neither the computer name nor the `Control Panel\Mouse` values it sets ever
show up in the guest's behaviour. Something between "the file is on the disk"
and "Windows has read it" is broken and has not been found. DirectPlay over
TCP/IP with an explicit address does not care, but Microsoft Networking will.


### Fixed, but worth knowing about

**The in-game pointer and the scrollbars fell to one config, together.**
`GUEST_RESOLUTION=1024,768` puts the guest at the framebuffer's own size, so
the pointer mapping is the identity and the world view fills the screen
with no scrollbars at all; PS/2 + `MouseSpeed=0` (verified live in the hive
with `win9x-hive-dump.py`) makes the guest curve 1:1 so the model's assumption
is simply true. Both were verified by template-matching the cursor sprite —
`scripts/cursor-locate.py` — after frame-diff measurements had twice produced
numbers wrong enough to send the work in the wrong direction. The templates in
`test-assets/` are resolution-specific: re-extract them if the guest mode
changes.


**Windows 98 has two live computer-name keys, and only one of them counts.**

```
HKLM\System\CurrentControlSet\Services\VxD\VNETSUP\ComputerName    <- looks right, is ignored
HKLM\System\CurrentControlSet\Control\ComputerName\ComputerName     <- what actually gets registered
```

Setting only the first left every clone announcing the image's baked-in name, so
the second guest onto the LAN hit *Error 38: the computer name you specified is
already in use on the network*, and never registered a name at all.

The two values in `VNETSUP` are the control that proves it — same file, same key,
same import — `Workgroup` landed while `ComputerName` did not. `Workgroup` has
one source, so VNETSUP's copy is used; `ComputerName` has two, and
`Control\ComputerName` wins. The second key looks NT-only. It is not.

A NetBIOS node-status probe is the fastest way to check this from outside the
guest, and it distinguishes "the registry says X" from "the machine announces X":

```
192.168.10.10   LOCO-00 <00> UNIQUE   LOCOLAND <00> GROUP
192.168.10.11   LOCO-01 <00> UNIQUE   LOCOLAND <00> GROUP
```

Before the fix, `.11` registered `LOCOLAND` and nothing else.


**Launching the game, and setting the guest's identity, both needed a mechanism
that runs before the desktop.** Driving the desktop icon over VNC never worked —
a double-click registers as two single clicks even at an 0.08s hold, and
click-then-Enter does not open it either, while the pointer is provably landing
on target. And the StartUp folder could never have set the computer name even in
principle: Windows reads it when it initialises networking at boot, and StartUp
runs at the end of logon.

Both are now off the GUI entirely:

* `WIN.INI` `[windows] run=` launches LEGO LOCO at logon. It takes a
  space-separated list of *programs* with no arguments, which is why it gets a
  bare 8.3 path — an earlier `run=regedit /s C:\LOCOID.REG` made Windows try to
  launch three separate things, one of which was an interactive Registry Editor
  that stole focus.
* `AUTOEXEC.BAT` calls `C:\LOCOINIT.BAT`, which merges `LOCOID.REG` using
  real-mode `REGEDIT.EXE /L:...SYSTEM.DAT /R:...USER.DAT`. At AUTOEXEC time
  Windows has not loaded, so the hives are not in use and the merge lands before
  anything reads them. This is the documented Win9x registry-recovery procedure,
  used here for its timing. Verified: the injected name is now in `SYSTEM.DAT`.

Both write a marker file (`LOCOINIT.LOG`, `LOCOSTUP.LOG`) so "the script did not
run" can be told apart from "the script ran and the setting did not stick" —
those two failures look identical from outside and cost an afternoon each.


Three bugs made the guest LAN look plumbed while carrying nothing. All three
were silent — every interface read healthy to `ip link`:

* **The tap had no carrier.** A tap only has carrier while a process holds its
  `/dev/net/tun` fd, and PCem's PCap backend attaches with libpcap and never
  opens it. Replaced with a veth pair.
* **The VXLAN mesh loop died on its first DNS miss.** Backgrounded under
  `set -euo pipefail`, and `getent hosts` exits 2 for a name that does not
  resolve. Ordinal 0 starts before ordinal 1 exists, so the one pod that also
  runs DHCP lost its peer list seconds after boot and never rebuilt it.
* **DHCP replies reached the guest with a broken UDP checksum.** A locally
  generated reply leaves the stack with `CHECKSUM_PARTIAL`, and since every
  device in the path advertises tx-checksumming the kernel never completes it.
  A kernel peer would not care; Windows 98 checksums in software, found it
  wrong, and dropped every OFFER. Fixed with `ethtool -K ... tx off`. The tell
  was that the guest's own DISCOVERs (checksummed by Windows) were accepted and
  it answered ARP (no checksum), so only checksummed L4 was dying.

Note for future captures: this Win98 image emits a nonsensical BOOTP `secs`
value and dnsmasq mirrors it back. It is not a symptom of anything.

## Tools

Built while debugging this container, because nothing existing answered the
question. `.claude/skills/win98-guest-forensics/` documents how to use them
together.

| Tool | What it is for |
|---|---|
| `scripts/win9x-hive-dump.py` | Read a Win9x CREG registry hive. hivex and chntpw are NT-only, so this is the only way to see what is actually in `SYSTEM.DAT`. `--find` marks hits live vs deleted; `--diff` compares two guests. |
| `scripts/nbt-names.py` | Ask a guest which NetBIOS names it has *registered* — what it announces, rather than what its registry says. |
| `scripts/vnc-drive.py` | Drive the guest GUI over RFB: move, click, type, screenshot. |
| `scripts/vnc-screenshot.py` | Single frame grab. |
| `scripts/pcem-snapshot.sh` | Package a guest disk as an OCI image. |

## Layout

| Path | Purpose |
|---|---|
| `Dockerfile` | 3 stages: build PCem v17, fetch BIOS ROMs, runtime |
| `entrypoint.sh` | disk → config → Xvfb → x11vnc → health → PCem → shutdown |
| `patches/vnc-mouse.py` | absolute-pointer support for remote clients |
| `scripts/pull-snapshot.sh` | curl-only OCI blob puller for the disk image |
| `scripts/health-server.py` | `/health` (readiness) and `/` (liveness) |
| `nvr-seed/` | known-good CMOS per board, for unattended first boot |
| `standalone/` | the original bring-up investigation and its log |
