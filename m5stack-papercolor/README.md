# Loco PaperColor — M5Stack PaperColor second screen

A low-refresh, full-colour second screen and controller for LEGO Loco instances.

The PaperColor does **not** speak VNC. A small gateway reuses the cluster's proven
`RfbFramebuffer` implementation, keeps the freshest guest framebuffer in memory,
and sends a single 600×400 JPEG only when the device requests one. Input messages
are injected immediately through RFB and do not wait for the E Ink refresh.

```text
Win98 / LEGO Loco
      │ raw RFB :5901
      ▼
RfbFramebuffer (live RGB, incremental updates)
      │
      ▼
PaperColor gateway  ───── input JSON ─────► RFB pointer events
      │
      └──── freshest 600x400 JPEG on demand ───► PaperColor
                                                  │
                                          Spectra 6 refresh
```

## Why pull frames instead of streaming

M5Stack specifies the 4.0" Spectra 6 panel at 600×400 with a typical full refresh
in the ~15–30 second range. Sending video at 5/10/30 fps would only create a stale
queue. The firmware therefore follows this loop:

1. request `frame.request`;
2. receive the newest framebuffer snapshot;
3. draw it and wait for the physical panel refresh to finish;
4. immediately request the next newest frame.

The displayed image is therefore always the newest frame available at the instant
a refresh cycle begins.

## Hardware

Target: **M5Stack PaperColor C151** (ESP32-S3, 600×400 six-colour E Ink, Wi-Fi).

PaperColor itself has **no built-in touchscreen**. The firmware supports:

- built-in BtnA / BtnB / BtnC as prev instance / inspect-click / next instance;
- an optional 4" capacitive overlay using a **GT911** controller on Port A I²C
  (SDA GPIO2, SCL GPIO3). Addresses `0x5D` and `0x14` are probed.

The touch overlay is optional; the device is fully usable with the three buttons.
If fitting an overlay, choose one whose active area matches the 600×400 panel and
wire 3V3/GND/SDA/SCL. INT/RST are not required by this simple polling driver.

## Layout

```text
m5stack-papercolor/
├── firmware/
│   ├── platformio.ini
│   └── src/main.cpp
└── gateway/
    └── server.js
```

## Gateway quick start

The gateway intentionally reuses packages already installed in `backend/`.

```bash
cd backend && npm install
cd ..

export PAPERCOLOR_INSTANCES='{
  "instance-0":{"host":"127.0.0.1","port":5901},
  "instance-1":{"host":"127.0.0.1","port":5902}
}'
node m5stack-papercolor/gateway/server.js
```

Default port: **3002**.

WebSocket URL used by the device:

```text
ws://<gateway-host>:3002/ws/papercolor/<instance-id>
```

Messages from firmware:

```json
{"type":"frame.request"}
{"type":"pointer","x":0.42,"y":0.55,"buttons":0}
{"type":"click","x":0.42,"y":0.55}
{"type":"instance.select","id":"instance-3"}
```

Server messages:

```json
{"type":"hello","width":600,"height":400,"instanceId":"instance-0"}
{"type":"instance.active","id":"instance-3"}
```

Binary messages are JPEG snapshots, already resized to exactly 600×400.

## Firmware

```bash
cd m5stack-papercolor/firmware
pio run
pio run -t upload
```

On first boot the device starts `LocoPaper-Setup`. Join it from a phone and enter:

- Wi-Fi credentials
- gateway host/IP
- gateway port (default `3002`)
- first instance ID (`instance-0`)
- instance count (normally `9`)

Hold **BtnA while booting** to reopen provisioning.

### Controls

| Input | Action |
|---|---|
| BtnA | previous instance + request fresh frame |
| BtnB | click centre of game screen |
| BtnC | next instance + request fresh frame |
| touch tap | click exact normalized position |
| touch drag | move pointer immediately |
| touch release | click where released |

Because E Ink is slow, touch/input is deliberately decoupled from display refresh.
The input reaches RFB immediately; the result becomes visible on the next completed
refresh. This is useful for deliberate navigation/inspection, not twitch gameplay.

## Next hardware-validation steps

1. Flash firmware and confirm M5Unified detects `board_M5PaperColor` and reports
   `600x400`.
2. Measure real full-refresh duration on this unit.
3. Photograph the six-colour conversion against the browser/VNC reference.
4. Fit/probe the GT911 overlay, then calibrate X/Y orientation if necessary.
5. Run the gateway against a live PCem instance and measure tap → VNC injection and
   snapshot-age-at-refresh-start separately.

Sources: M5Stack PaperColor documentation and current M5Unified support for
`board_M5PaperColor`.