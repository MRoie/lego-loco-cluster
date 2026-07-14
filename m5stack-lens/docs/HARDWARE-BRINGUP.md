# Loco Lens — StopWatch hardware bring-up log

First flash + live run of the firmware on a **real M5Stack StopWatch (C152)**,
driving a live circular crop of a running Lego Loco (Win98/QEMU) instance. This
records what was actually observed on the device and the fixes it drove, so the
next person doesn't re-derive them.

Companion docs: [STOPWATCH-HARDWARE-RESEARCH.md](STOPWATCH-HARDWARE-RESEARCH.md)
(hardware reference) and [E2E-VERIFICATION.md](E2E-VERIFICATION.md) (headless
software-watch e2e).

## Verified good

- **Board autodetect works.** M5GFX identifies the StopWatch by I2C-probing
  GPIO47/48 (CST820 touch 0x15 + BMI270 0x68 + RX8130 0x32, no NFC). On-device
  it reported `board = 30` (`board_M5StopWatch`) and configured the CO5300 QSPI
  AMOLED at **468×468** — confirmed by the on-display diagnostic.
- **Octal PSRAM is mandatory.** M5GFX gates the *entire* CO5300 panel init on
  `CONFIG_SPIRAM_MODE_OCT`; without it the board is named but the panel is never
  configured (garbage/partial display). `platformio.ini` already sets
  `board_build.arduino.memory_type = qio_opi`; the build links the `qio_opi`
  arduino-esp32 variant (verified in the map file) so this is satisfied.
- **Full pipeline is live:** QEMU VNC (:5901) → standalone lens-server (:3001) →
  PNG circular crop → watch over Wi-Fi. Measured ~9 fps of 466×466 PNG frames.

## Gotchas & fixes (device-specific)

### 1. Serial/USB console yields nothing — use the display
`ARDUINO_USB_MODE=1` (HWCDC over USB-Serial-JTAG, `303A:1001`) is correct and
esptool flashes/resets fine over it, but **no app `Serial`/`printf` output ever
reaches the host** on this unit (0 bytes across resets, port held open, both DTR
states). Do not rely on serial for on-device debug. Instead the firmware
**self-reports on the panel** via `drawDiagGrid()` (see below).

### 2. Default rotation is 90° off — upright is rotation 0
Out of the box M5Unified brings the panel up at rotation 1, so everything is
rotated 90° CCW. Upright is **rotation 0**. The firmware defaults `g_rot = 0`
and persists any recalibration in NVS (`locolens/rot`).

### 3. On-display diagnostic + rotation calibrator
Because serial is dead, **hold KEYA while powering on** to enter the calibrator:
a numbered 4×4 colour grid with `b<board> r<rot> <W>x<H>` printed in five places
(survives any offset). **KEYB** cycles rotation 0→1→2→3 live; **KEYA** accepts
(saves to NVS) and continues to Wi-Fi setup. A photo of this screen is the whole
diagnosis — board id, configured size, and which framebuffer region is visible.

### 4. Frame draw: auto-fit, centred, no per-frame clear
- Draw with `drawPng(data, len, w/2, h/2, w, h, 0,0, 0.0f,0.0f, middle_center)` —
  `scale_x = 0.0` means *auto-fit to maxWidth/maxHeight*, so the crop fills the
  round panel regardless of the server crop size, centred.
- **Do not** `fillScreen()` before each frame and **do not** route through a
  PSRAM `M5Canvas` sprite: the per-frame clear caused visible flashing at ~10
  fps, and `pushSprite` from a PSRAM sprite produced a partial "almond" render.
  Drawing the auto-fit frame straight to the panel overwrites the whole square
  each time (nothing stale to flash); the transparent corners fall outside the
  round bezel and are never seen.

## Backend changes this drove

- **`LENS_CROP_SIZE` honoured** (`routes/watch.js`), default **466** to match the
  panel 1:1. Was previously fixed small (360), which the watch drew off-centre.
- **`staleMs` 250 → 5000** (`services/lensBridge.js`). The Win98 guest is often
  static; at 250 ms every idle frame was dropped as "stale" and the watch got
  nothing. 5 s keeps the last real frame flowing.
- **Periodic full framebuffer refresh** (`services/rfbFramebuffer.js`): request a
  full RFB update every 500 ms so a fresh frame exists even when the guest isn't
  redrawing; timer cleaned up on `close()`.

## Runbook — live single-instance lens (no cluster)

Host: Windows, repo on `G:`. Toolchain kept on `G:` so `C:` isn't needed.

**Build + flash from G:** (C: was full; keep temp off it)
```sh
export PLATFORMIO_CORE_DIR=G:/loco-build/pio-core
export TMP=G:/loco-build/tmp TEMP=G:/loco-build/tmp TMPDIR=G:/loco-build/tmp
cd m5stack-lens/firmware
pio run -t upload --upload-port COM3     # native-USB reset works ("Hard resetting via RTS pin")
```

**Run the standalone lens-server** (taps QEMU VNC :5901, serves :3001):
```sh
export NODE_PATH=<repo>/backend/node_modules   # lens-server.js lives elsewhere; point Node at the deps
export LENS_PORT=3001 LENS_CROP_SIZE=466
export LENS_INSTANCES='{"instance-0":{"host":"127.0.0.1","port":5901},"local":{"host":"127.0.0.1","port":5901}}'
node golden-image/android/lens-server.js
```
Needs `express ws rfb2 winston winston-daily-rotate-file sharp` in
`backend/node_modules` (sharp is required — without it the encoder falls back to
raw RGBA, which the watch can't decode).

**Windows Firewall:** the Wi-Fi profile is *Public*, which blocks inbound by
default. Allow the port (elevated):
```powershell
New-NetFirewallRule -DisplayName "Loco Lens 3001" -Direction Inbound -Protocol TCP -LocalPort 3001 -Action Allow -Profile Any
```

**On the watch:** first boot → join `LocoLens-Setup` AP → enter Wi-Fi + bridge
host (`192.168.1.236`), port `3001`, instance `instance-0`. It then streams the
live crop. Controls: drag = pan · tap = inspect · long-press = close · KEYB =
zoom in · KEYA = zoom out.

## Build stats
arduino-esp32 3.2.0 (pioarduino 54.03.20), M5Unified 0.2.18 / M5GFX 0.2.25 —
Flash **43.7%** (1,462,150 B), RAM **15.7%**. Merged flashable image:
`flasher/firmware/loco-lens.bin` (~1.53 MB, app at 0x10000).
