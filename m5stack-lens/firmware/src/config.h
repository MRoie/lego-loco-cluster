#pragma once
// Loco Lens — device + connection configuration.
// Copy to config.local.h and edit, or provision at runtime over serial/BLE.
// Do NOT commit real Wi-Fi credentials.

// ---- Wi-Fi ----
#ifndef LOCO_WIFI_SSID
#define LOCO_WIFI_SSID     "YOUR_WIFI"
#endif
#ifndef LOCO_WIFI_PASS
#define LOCO_WIFI_PASS     "YOUR_PASS"
#endif

// ---- Lens bridge (the backend running the cluster) ----
// The watch connects to ws://<host>:<port>/ws/lens/<instanceId>.
#ifndef LOCO_BRIDGE_HOST
#define LOCO_BRIDGE_HOST   "192.168.1.50"
#endif
#ifndef LOCO_BRIDGE_PORT
#define LOCO_BRIDGE_PORT   3001
#endif
#ifndef LOCO_INSTANCE_ID
#define LOCO_INSTANCE_ID   "instance-0"
#endif

// ---- Round display ----
// 240x240 GC9A01 is the common round panel; the crop is drawn centered.
#define LENS_DISPLAY_W     240
#define LENS_DISPLAY_H     240
// The bridge sends a square crop (default 400px); we downscale to the panel.

// ---- Interaction tuning ----
#define LENS_TAP_MS        250   // < this = tap
#define LENS_LONGPRESS_MS  700   // > this = long press
#define LENS_MOVE_GAIN     0.6f  // touch-drag → lens.move sensitivity
#define LENS_PING_MS       5000  // keepalive interval
