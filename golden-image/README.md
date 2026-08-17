# Win98 + Lego Loco Golden Image & Loco Lens Foundation

Reproducible pipeline to run the actual Windows 98 + Lego Loco qcow2 on Android
(Termux/QEMU), provision it into a clean sealed **golden image**, publish that
image multi-arch to GHCR, and drive it from an M5Stack StopWatch "Loco Lens" —
a circular second-screen crop of the running game.

> The M5Stack watch is **not** a standalone emulator. The game keeps running in
> Windows 98 under QEMU; the watch is a synchronized second-screen controller
> that shows a circular crop of the real framebuffer and injects real input.

## Layout

```
golden-image/
├── android/      bootstrap + reusable QEMU launcher + run/stop
├── image/        import → work overlay → seal → OCI context
├── guest/        LOCOBOOT.BAT boot sentinel
├── tests/        qmp.py, rfb_probe.py, lens_crop.py, e2e.sh (host acceptance)
└── docs/         driver checklist, performance profiles, acceptance criteria
```

Proprietary assets live under `golden-image/assets/private/` and are gitignored:
`win98-base.qcow2`, `softgpu.iso`, `win98-cd.iso`, `lego-loco.iso`, `patchmem/`.

## Quickstart (Android / Termux)

```bash
# 1. Stand up a provisioning VM from your current Android overlay
golden-image/android/bootstrap-android.sh

# 2. Connect a VNC viewer to 127.0.0.1:5901 (password in build/secrets/vnc-password)
#    Follow docs/DRIVER-INSTALL-CHECKLIST.md inside Windows 98.

# 3. After a CLEAN shutdown, seal the golden image
golden-image/image/seal-golden-image.sh \
  golden-image/build/work/win98-loco-provisioning.qcow2 \
  golden-image/build/output/win98-loco-safe512.qcow2 safe512

# 4. Boot the sealed golden image (fresh overlay, base stays immutable)
golden-image/android/run-golden.sh --profile safe512

# 5. Host acceptance checks
golden-image/tests/e2e.sh
```

## Profiles

| Profile | Guest RAM | Use |
|---------|-----------|-----|
| `safe512` | 512 MB | Mandatory baseline; safe everywhere. Default. |
| `highmem1024` | 1024 MB | Only after a validated Win98 high-memory patch. |

Windows 98 is always single-vCPU. Host-side TCG translation cache is sized
independently (`--tcg-cache`, default 1024 MB). See `docs/PERFORMANCE-PROFILES.md`.

## Loco Lens backend

The lens bridge attaches to the QEMU **VNC/RFB framebuffer**, not any host
desktop — so it works identically on Android, PC, containers and k8s.

- `backend/services/rfbFramebuffer.js` — live framebuffer from an instance's VNC.
- `backend/services/lensCrop.js` — circular crop geometry + normalized pointer mapping.
- `backend/services/lensEncoder.js` — PNG/JPEG/raw crop encoding.
- `backend/services/lensBridge.js` — fps pacing, stale-frame dropping, control routing.
- `backend/protocol/watchProtocol.js` — the watch JSON message schema.
- `backend/routes/watch.js` — `/api/watch/*` REST + `/ws/lens/:instanceId` WebSocket.

Watch control messages (all coordinates normalized to `[0,1]`):

```json
{ "type": "lens.move", "dx": 0.012, "dy": -0.006 }
{ "type": "lens.pointer", "x": 0.431, "y": 0.618, "buttons": 1 }
{ "type": "lens.inspect" }
{ "type": "instance.select", "id": "instance-2" }
```

Firmware is intentionally out of scope for this foundation (see the PR body).
