# Loco Lens — end-to-end verification & real-watch bring-up

## What's verified (server side, 2026-07-11)

A single-instance stack was run and the watch's exact endpoint proven end to end:

```
QEMU (clean golden Win98 + Loco)  ──VNC :5901──►  lens-server (static: instance-0 → :5901)
                                                        │  /ws/lens/instance-0
                                            lens-smoke (headless watch stand-in)
```

- `lens-server` (the **shipping Android bundle**, shim logger, no k8s) came up
  healthy: `/healthz` → `{"ok":true,"instances":["instance-0"]}`.
- `lens-smoke` (a headless stand-in for the watch) connected to
  `ws://…/ws/lens/instance-0` and in ~14 s received **140 circular PNG frames**
  and sent every control message the watch sends
  (`lens.move`, `lens.zoom`, `lens.pointer`, `lens.inspect`, `mouse.button`,
  `lens.close`, `watch.ping`) with **0 server errors**. Result: **PASS**.
- Evidence: `evidence/e2e-full-framebuffer.png` (the guest screen) and
  `evidence/e2e-lens-circular-crop.png` (the round crop the watch receives — a
  magnified slice of that framebuffer with the circular mask).

So the endpoint the watch talks to is proven. The physical watch just needs to
be flashed and pointed at it.

## Bring the single instance up yourself

```bash
# 1. one QEMU with the clean golden, VNC on :5901
docker run -d --name loco-emu -v "$PWD/containers:/img:ro" -p 5901:5901 \
  debian:bookworm-slim bash -c 'apt-get update >/dev/null && \
  apt-get install -y qemu-system-x86 >/dev/null && \
  exec qemu-system-i386 -M pc -cpu pentium3 -m 512 -smp 1 -snapshot \
    -hda /img/win98-loco-golden-safe512.qcow2 -vga std -vnc 0.0.0.0:1 \
    -netdev user,id=n0 -device ne2k_pci,netdev=n0 -rtc base=localtime \
    -qmp unix:/tmp/qmp.sock,server,nowait -no-shutdown'

# 2. the lens server, pointed at that VNC (static single instance)
cd golden-image/android
LENS_INSTANCES='instance-0=127.0.0.1:5901' LENS_PORT=3001 \
  LENS_BACKEND_DIR="$PWD/../../backend" node lens-server.js
#   (on a phone this is exactly what run-all.sh does, instance id 'local')

# 3. prove it without hardware (software watch):
node m5stack-lens/tools/lens-smoke.js --host localhost --port 3001 --instance instance-0
```

`lens-smoke` is your pre-flight: if it prints PASS, the real watch will connect.

## Flash the real M5Stack StopWatch

1. **Set the target in `m5stack-lens/firmware/src/config.h`**: Wi-Fi SSID/pass,
   `LOCO_BRIDGE_HOST` = the machine running lens-server, `LOCO_INSTANCE_ID`
   (`instance-0` here, `local` on the phone bundle).
2. **Match your display.** `platformio.ini` targets a generic ESP32-S3 + round
   GC9A01 via TFT_eSPI. On a genuine M5Stack board, swap the display layer for
   **M5Unified/M5GFX** (auto-detects the panel) — that's the most reliable path
   and avoids hand-editing pins.
3. **Build + flash**:
   ```bash
   cd m5stack-lens/firmware
   pio run                 # build
   pio run -t upload       # flash over USB
   ```
   Or serve `m5stack-lens/flasher/` (ESP Web Tools) after dropping the merged
   binary in `flasher/firmware/` — see `m5stack-lens/README.md`.

## Test each function e2e (watch ↔ live instance)

With the watch flashed and connected (it sends `watch.hello`, the bridge replies
`instance.active`), verify each interaction — cross-check against `lens-smoke`,
which drives the same messages:

| Watch action | Message sent | Expect on the watch / guest |
|--------------|--------------|-----------------------------|
| (connect) | `watch.hello` | round display shows a live circular crop of the game |
| Drag | `lens.move {dx,dy}` | the crop pans across the city |
| Tap | `lens.inspect` | left-click at the lens centre in-game (object inspected) |
| Long-press | `lens.close` | inspection closes |
| Left/right button | `lens.zoom {delta}` | crop magnifies out / in |
| Pointer | `lens.pointer {x,y,buttons}` | cursor moves to the mapped guest pixel |
| (idle) | `watch.ping` | connection stays alive |

Frame-age target < 250 ms, input round-trip < 150 ms — measure on-device.

## Notes / knowns
- The guest boots slowly under TCG on constrained hosts; the lens streams
  whatever is rendered (splash → desktop → game) — it doesn't gate on readiness.
- `sharp` (PNG encode) is optional; without it the bridge sends raw frames and
  the watch decodes those instead.
- The firmware is **build-ready but not yet flashed on hardware** — the display
  layer is the one thing to match to your exact board.
