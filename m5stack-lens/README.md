# Loco Lens — M5Stack StopWatch

Firmware + web flasher for the **M5Stack StopWatch** (C152) so it acts as a
synchronized second screen for a running Lego Loco instance: the 1.75" round
AMOLED shows a live **circular crop** of the real game framebuffer (streamed
from the backend lens bridge) and sends **touch/button control** back into the
guest.

> The watch is not an emulator and never speaks RFB. It exchanges JSON control
> messages over `/ws/lens/:instanceId`; the backend does the framebuffer
> capture, circular crop, and RFB input injection. See `backend/routes/watch.js`
> and `m5stack-lens/docs/E2E-VERIFICATION.md`.

## Target hardware — M5Stack StopWatch (C152)
- ESP32-S3R8 (16 MB flash, 8 MB PSRAM), Wi-Fi 2.4 GHz.
- 1.75" round **AMOLED 466×466**, CO5300 (QSPI); **CST820B** touch.
- Buttons: KEYA (yellow, G2) and KEYB (blue, G1) + power.
- `M5Unified`'s `M5.begin()` configures the display, touch, buttons and power.

Docs: https://docs.m5stack.com/en/core/StopWatch

## Layout
```
m5stack-lens/
├── firmware/      M5Unified firmware (ESP32-S3 / StopWatch)
│   ├── platformio.ini
│   └── src/{main.cpp, config.h}
├── flasher/       ESP Web Tools browser flasher (LEGO-themed)
│   ├── index.html
│   └── manifest.json   (firmware/*.bin added by the release build)
├── tools/         lens-smoke.js — headless "software watch" pre-flight
└── docs/          E2E-VERIFICATION.md
```

## Build + flash

First set your target in `src/config.h`: Wi-Fi SSID/pass, `LOCO_BRIDGE_HOST`
(the machine running lens-server / the cluster backend), and `LOCO_INSTANCE_ID`
(`instance-0` for the cluster, `local` for the Android bundle).

**Enter download mode before flashing:** hold the reset/power button ~2 s until
the internal **green LED** lights, then release.

### Arduino IDE (matches M5's docs)
- ESP32 board manager **≥ 3.3.7**, board **"M5StopWatch"**.
- Install **M5Unified ≥ 0.2.15** and **M5GFX ≥ 0.2.21** (+ prompted deps),
  plus **WebSockets** (links2004) and **ArduinoJson**.
- Open `src/main.cpp`, select the port, Upload.

### PlatformIO
The StopWatch needs arduino-esp32 3.x, which official PlatformIO doesn't ship
yet — `platformio.ini` uses the community **pioarduino** platform for it.
```bash
cd m5stack-lens/firmware
pio run                 # build
pio run -t upload       # flash over USB (download mode first)
```

### Web flasher
Merge the build output and drop it in `flasher/firmware/`, then serve
`flasher/` and open it in desktop Chrome/Edge (WebSerial):
```bash
esptool.py --chip esp32s3 merge_bin -o m5stack-lens/flasher/firmware/loco-lens.bin \
  0x0 .pio/build/*/bootloader.bin 0x8000 .pio/build/*/partitions.bin \
  0x10000 .pio/build/*/firmware.bin
```

## Verify before you flash
`m5stack-lens/tools/lens-smoke.js` is a headless "software watch" — it connects
to `/ws/lens/:instance`, checks frames decode, and drives every control message.
If it prints PASS, the real watch will connect. See `docs/E2E-VERIFICATION.md`.

## Interaction
| Input | Message | Effect in-game |
|-------|---------|----------------|
| Drag | `lens.move {dx,dy}` | pan the lens over the city |
| Tap | `lens.inspect` | left-click the object under the lens centre |
| Long-press | `lens.close` | close inspection |
| KEYA / KEYB | `lens.zoom {delta}` | zoom out / in |
| (idle) | `watch.ping` | keepalive |

The bridge streams **PNG** frames by default (M5GFX decodes them and draws them
centred on the round panel); it can send JPEG on a bandwidth budget.
