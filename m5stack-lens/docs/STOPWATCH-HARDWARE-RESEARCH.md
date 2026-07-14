# M5Stack StopWatch (C152) — hardware research & Loco Lens insights

Source: https://docs.m5stack.com/en/core/StopWatch (fetched 2026-07-11) and the
linked sub-pages / datasheets. This is the reference behind the M5Unified
firmware in `../firmware/`.

## Hardware summary

| Subsystem | Part | Bus / pins | Notes for Loco Lens |
|-----------|------|------------|---------------------|
| SoC | ESP32-S3R8, dual LX7 @240 MHz, 16 MB flash, **8 MB PSRAM** | — | PSRAM is plenty for full-frame lens buffers; S3 native USB = ESP Web Tools flashing |
| Display | **1.75" round AMOLED 466×466**, CO5300 | QSPI: G39,40,38,41,42,46,45 | A *round* panel that natively matches the circular lens crop — no wasted corners |
| Touch | **CST820B** | I2C: G47,G48; INT G13 | drag / tap / long-press gestures |
| Buttons | KEYA (yellow) / KEYB (blue) + power | **G2 / G1** | zoom out / in (or train slower/faster) |
| IMU | **BMI270** 6-axis | I2C @0x68 | **tilt-to-drift the lens** (context doc's optional IMU idea) |
| Vibration | motor via **M5IOE1** IO expander | I2C | **haptic** for inspect / train speed / e-stop |
| RTC | RX8130CE | I2C @0x32 | timestamp captures; wake scheduling |
| Mic + codec | MEMS mic + **ES8311** | I2C @0x18, I2S G18,17,16,15,21 | voice control path (M5's Xiaozhi assistant runs on this board) |
| Speaker | AW8737A amp + 1 W | — | audio cues |
| Power | 450 mAh batt, **M5PM1** PMIC | I2C | untethered use; M5.begin() handles core power |
| Connectivity | Wi-Fi 2.4 GHz (**no BLE**) | — | watch↔bridge is Wi-Fi WebSocket (already the design) |

Flashing: hold reset/power ~2 s until the internal **green LED**, then USB-C.
Factory firmware "M5StopWatch-UserDemo" via Easyloader.

## Toolchain (validated in firmware/)
- ESP32 Arduino core **≥ 3.3.7**, **M5Unified ≥ 0.2.15**, **M5GFX ≥ 0.2.21**.
- `M5.begin(cfg)` configures display + touch + buttons + power for this board.
- M5GFX has built-in `drawPng`/`drawJpg` → the watch decodes lens frames with
  one call; no separate PNG lib.
- PlatformIO: official `espressif32` still ships core 2.x, so we use the
  **pioarduino** platform to get core 3.x. Arduino IDE (board "M5StopWatch")
  is the primary documented route.

## Insights for the Loco Lens

1. **The round 466×466 AMOLED is a near-perfect match for the circular lens.**
   Our crop is already a circle with transparent corners; on a round panel there
   are no wasted corners and the bezel *is* the lens ring. Action: raise the
   bridge crop `size` toward 466 (currently 400) so it fills the panel 1:1 with
   no upscale — set `LensBridge({ size: 466 })` for StopWatch clients.

2. **PSRAM (8 MB) removes the frame-size worry.** We can push higher-quality
   crops (even brief full-res regions) without RAM pressure; JPEG at ~466² is
   trivial. The current 8–12 fps / <250 ms targets are comfortable.

3. **BMI270 IMU unlocks tilt-to-pan** — the context doc's "optional IMU tilt to
   drift lens." A new control message `lens.tilt {gx,gy}` (or reuse `lens.move`)
   lets you nudge the lens by tipping the watch — hands-free panning while a
   train is followed. Backend already clamps `lens.move`; only the firmware +
   one message need adding.

4. **Vibration (M5IOE1) gives the train-mode haptics for free.** The context
   doc wanted haptic feedback for speed and emergency stop. Add a downstream
   `watch.haptic {ms}` message the bridge can emit on inspect-hit / e-stop, and
   drive the motor via M5IOE1. Pure additive; no lens-path change.

5. **Two buttons map cleanly to the two documented modes.** City Lens: KEYA/KEYB
   = zoom out/in. Train mode (after `lens.inspect` selects a train): KEYA/KEYB =
   slower/faster, long-press KEYB = reverse, center tap = stop/start — exactly
   the context doc's train controls, achievable with the existing button events
   plus a mode flag the firmware toggles on inspect.

6. **Mic + ES8311 + M5's Xiaozhi stack = a later voice path.** Out of scope now,
   but the same board M5 ships a voice assistant on could later drive
   `instance.select` / `lens.inspect` by voice. Parked.

7. **No BLE — Wi-Fi WebSocket was the right call.** The whole lens design already
   assumes Wi-Fi to `/ws/lens/:instanceId`; nothing to change. Keep the bridge
   host reachable on the 2.4 GHz LAN the watch joins.

8. **Round display + touch drift correction.** CST820B is single-touch; our
   drag→`lens.move` mapping fits. For inspect precision on a small round screen,
   consider a brief crosshair overlay at the lens centre (firmware-side draw
   after each frame) so taps land where the user expects.

## Suggested next steps (small, additive)
- Bridge: make crop `size` configurable per-connection (query param or
  `watch.hello` capability) and default StopWatch to 466.
- Protocol: add `lens.tilt` (IMU pan) and `watch.haptic` (downstream) to
  `watchProtocol.js` — both are tiny, testable additions.
- Firmware: mode flag (City ↔ Train) toggled on `lens.inspect`, remap buttons
  accordingly; optional crosshair overlay.
