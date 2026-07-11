#pragma once
// Loco Lens — M5Stack StopWatch config. Edit before flashing (or provision
// later). Do NOT commit real Wi-Fi credentials.

// ---- Wi-Fi (StopWatch is 2.4 GHz only) ----
#ifndef LOCO_WIFI_SSID
#define LOCO_WIFI_SSID     "YOUR_WIFI"
#endif
#ifndef LOCO_WIFI_PASS
#define LOCO_WIFI_PASS     "YOUR_PASS"
#endif

// ---- Lens bridge (the machine running lens-server / the cluster backend) ----
// The watch connects to ws://<host>:<port>/ws/lens/<instanceId>.
#ifndef LOCO_BRIDGE_HOST
#define LOCO_BRIDGE_HOST   "192.168.1.50"
#endif
#ifndef LOCO_BRIDGE_PORT
#define LOCO_BRIDGE_PORT   3001
#endif
// Cluster: an instance id from discovery (e.g. "instance-0").
// Android / single host bundle: the static registry id ("local").
#ifndef LOCO_INSTANCE_ID
#define LOCO_INSTANCE_ID   "instance-0"
#endif

// ---- Interaction tuning ----
// Display is the StopWatch's 466x466 round AMOLED (queried at runtime via
// M5.Display); the bridge sends a circular crop that we draw centred.
#define LENS_TAP_MS        250   // <= this (with little movement) = tap
#define LENS_LONGPRESS_MS  700   // >= this = long press
#define LENS_MOVE_GAIN     0.6f  // touch-drag → lens.move sensitivity
#define LENS_PING_MS       5000  // keepalive interval
