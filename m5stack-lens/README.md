# Loco Lens — M5Stack StopWatch

Firmware + web flasher for the round ESP32-S3 "StopWatch" that acts as a
synchronized second screen for a running Lego Loco instance: it shows a live
**circular crop** of the real game framebuffer (streamed from the backend lens
bridge) and sends **touch/button control** back into the guest.

> The watch is not an emulator and never speaks RFB. It talks JSON control
> messages to `/ws/lens/:instanceId`; the backend does the framebuffer capture,
> circular crop, and RFB input injection. See `backend/routes/watch.js`.

## Layout
```
m5stack-lens/
├── firmware/      PlatformIO project (ESP32-S3 + round display)
│   ├── platformio.ini
│   └── src/{main.cpp, config.h}
├── flasher/       ESP Web Tools browser flasher (LEGO-themed)
│   ├── index.html
│   └── manifest.json   (firmware/*.bin added by the release build)
└── docs/
```

## Build + flash
```bash
cd m5stack-lens/firmware
# edit src/config.h: Wi-Fi + LOCO_BRIDGE_HOST + LOCO_INSTANCE_ID
pio run                       # build
pio run -t upload             # flash over USB

# for the web flasher, merge the binaries and drop them in flasher/firmware/:
esptool.py --chip esp32s3 merge_bin -o flasher/firmware/loco-lens.bin \
  0x0 .pio/build/*/bootloader.bin 0x8000 .pio/build/*/partitions.bin \
  0x10000 .pio/build/*/firmware.bin
```
Then serve `flasher/` (any static host) and open it in desktop Chrome/Edge.

## Protocol
The firmware speaks the schema in `backend/protocol/watchProtocol.js`
(normalized `[0,1]` coordinates). Interaction mapping:

| Input | Message |
|-------|---------|
| Drag | `lens.move {dx,dy}` |
| Tap | `lens.inspect` |
| Long-press | `lens.close` |
| Side buttons | `lens.zoom {delta}` |
| (keepalive) | `watch.ping` |

The bridge streams **PNG** lens frames by default (preserves the circular
transparent corners); the firmware decodes and center-blits them to the round
panel.

## Status
Build-ready source targeting a generic ESP32-S3 + GC9A01-class round display.
**Not yet flashed/verified on physical hardware** — pin/board specifics in
`config.h` and `platformio.ini` should be matched to your exact StopWatch unit
(M5Unified/M5GFX is a drop-in for the display layer on genuine M5Stack boards).
This is the integration foundation to pair with the clean golden Android image.
