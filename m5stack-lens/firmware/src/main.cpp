// ============================================================================
// Loco Lens — M5Stack StopWatch (C152) firmware
// ============================================================================
// Hardware (per https://docs.m5stack.com/en/core/StopWatch):
//   ESP32-S3R8, 1.75" round AMOLED 466x466 (CO5300 QSPI), CST820B touch,
//   two buttons KEYA(G2)/KEYB(G1), Wi-Fi 2.4GHz. M5Unified's M5.begin(cfg)
//   configures the display, touch, buttons and power for this board.
//
// This is a synchronized second screen for a running Lego Loco instance: the
// round display shows a live circular crop of the real game framebuffer
// streamed from the backend lens bridge over WebSocket; touch and buttons are
// sent back as normalized control messages (watchProtocol.js) that the bridge
// injects into the guest via RFB. The watch never speaks RFB.
//
//   recv: binary PNG lens frame  -> M5.Display.drawPng(...)   (M5GFX decodes)
//   send: lens.move / lens.pointer / lens.inspect / lens.close / lens.zoom /
//         mouse.button / watch.hello / watch.ping   (all coords normalized [0,1])
//
// Build: Arduino IDE (board "M5StopWatch", esp32 board mgr >=3.3.7, M5Unified
// >=0.2.15, M5GFX >=0.2.21) or PlatformIO — see platformio.ini / README.md.
// ============================================================================
#include <M5Unified.h>
#include <WiFi.h>
#include <WiFiManager.h>
#include <Preferences.h>
#include <WebSocketsClient.h>
#include <ArduinoJson.h>
#include "config.h"

static WebSocketsClient ws;
static bool connected = false;
static uint32_t lastPing = 0;

// Runtime config (Wi-Fi via WiFiManager; bridge via captive-portal fields,
// persisted in NVS) so one flashed binary works for anyone.
static Preferences prefs;
static char   g_host[64]   = LOCO_BRIDGE_HOST;
static int    g_port       = LOCO_BRIDGE_PORT;
static char   g_instance[32] = LOCO_INSTANCE_ID;

// Touch gesture state → lens.move / lens.inspect / lens.close.
static bool touching = false;
static uint32_t touchStart = 0;
static int lastX = 0, lastY = 0, startX = 0, startY = 0;

// ---------------------------------------------------------------------------
// Control messages
// ---------------------------------------------------------------------------
static void sendJson(const JsonDocument& d) { String s; serializeJson(d, s); ws.sendTXT(s); }
static void sendMove(float dx, float dy)   { JsonDocument d; d["type"]="lens.move"; d["dx"]=dx; d["dy"]=dy; sendJson(d); }
static void sendZoom(float delta)          { JsonDocument d; d["type"]="lens.zoom"; d["delta"]=delta; sendJson(d); }
static void sendInspect()                  { JsonDocument d; d["type"]="lens.inspect"; sendJson(d); }
static void sendClose()                    { JsonDocument d; d["type"]="lens.close"; sendJson(d); }
static void sendPointer(float x, float y, int b) {
  JsonDocument d; d["type"]="lens.pointer"; d["x"]=x; d["y"]=y; d["buttons"]=b; sendJson(d);
}

// ---------------------------------------------------------------------------
// Lens frame → round display (M5GFX decodes PNG/JPEG and honours alpha)
// ---------------------------------------------------------------------------
static void drawLensFrame(const uint8_t* data, size_t len) {
  // Draw centred; M5GFX auto-detects the crop dimensions. A slightly smaller
  // crop than the panel just leaves a thin ring inside the round bezel.
  const int cx = M5.Display.width() / 2, cy = M5.Display.height() / 2;
  const int w = M5.Display.width(),      h = M5.Display.height();
  // maxWidth/maxHeight scale the crop to fit the panel; middle_center puts its
  // centre at (cx,cy). scale 0 = auto-fit within the max box.
  if (len > 4 && data[0] == 0x89 && data[1] == 0x50) {          // PNG
    M5.Display.drawPng(data, len, cx, cy, w, h, 0, 0, 0.0f, 0.0f, datum_t::middle_center);
  } else if (len > 3 && data[0] == 0xFF && data[1] == 0xD8) {   // JPEG
    M5.Display.drawJpg(data, len, cx, cy, w, h, 0, 0, 0.0f, 0.0f, datum_t::middle_center);
  }
}

// ---------------------------------------------------------------------------
// WebSocket events
// ---------------------------------------------------------------------------
static void onWs(WStype_t type, uint8_t* payload, size_t len) {
  switch (type) {
    case WStype_CONNECTED: {
      connected = true;
      M5.Display.fillScreen(TFT_BLACK);
      JsonDocument d; d["type"]="watch.hello"; d["watchId"]=WiFi.macAddress(); d["fw"]=LOCO_LENS_FW_VERSION;
      sendJson(d);
      break;
    }
    case WStype_DISCONNECTED:
      connected = false;
      M5.Display.fillScreen(TFT_BLACK);
      M5.Display.setTextDatum(middle_center);
      M5.Display.drawString("reconnecting...", M5.Display.width()/2, M5.Display.height()/2);
      break;
    case WStype_BIN:
      drawLensFrame(payload, len);
      break;
    default: break;
  }
}

// ---------------------------------------------------------------------------
// Input: touch drag → lens.move; tap → lens.inspect; long-press → lens.close;
// KEYA → zoom out, KEYB → zoom in.
// ---------------------------------------------------------------------------
static void pollInput() {
  M5.update();

  auto t = M5.Touch.getDetail();
  uint32_t now = millis();
  if (t.isPressed()) {
    if (!touching) { touching = true; touchStart = now; startX = lastX = t.x; startY = lastY = t.y; }
    else {
      float dx = (t.x - lastX) / (float)M5.Display.width()  * LENS_MOVE_GAIN;
      float dy = (t.y - lastY) / (float)M5.Display.height() * LENS_MOVE_GAIN;
      if (fabsf(dx) > 0.002f || fabsf(dy) > 0.002f) { sendMove(dx, dy); lastX = t.x; lastY = t.y; }
    }
  } else if (touching) {                       // released
    uint32_t held = now - touchStart;
    int moved = abs(t.x - startX) + abs(t.y - startY);
    if (held >= LENS_LONGPRESS_MS)         sendClose();
    else if (held <= LENS_TAP_MS && moved < 12) sendInspect();
    touching = false;
  }

  if (M5.BtnA.wasPressed()) sendZoom(-0.25f);  // KEYA (yellow, G2) — zoom out
  if (M5.BtnB.wasPressed()) sendZoom( 0.25f);  // KEYB (blue,   G1) — zoom in
}

// ---------------------------------------------------------------------------
static void banner(const char* line1, const char* line2 = nullptr) {
  M5.Display.fillScreen(TFT_BLACK);
  M5.Display.setTextDatum(middle_center);
  int cx = M5.Display.width() / 2, cy = M5.Display.height() / 2;
  M5.Display.drawString(line1, cx, line2 ? cy - 16 : cy);
  if (line2) M5.Display.drawString(line2, cx, cy + 16);
}

void setup() {
  auto cfg = M5.config();
  M5.begin(cfg);                               // display + touch + buttons + power
  M5.Display.setBrightness(160);
  M5.Display.setTextSize(M5.Display.height() / 200);
  banner("LOCO LENS");
  delay(400);
  M5.update();

  // Load persisted bridge config (falls back to config.h defaults).
  prefs.begin("locolens", true);
  prefs.getString("host", g_host, sizeof(g_host));
  g_port = prefs.getInt("port", g_port);
  prefs.getString("inst", g_instance, sizeof(g_instance));
  prefs.end();

  // Hold KEYA at boot to wipe saved Wi-Fi + config and re-provision.
  bool forceSetup = M5.BtnA.isPressed();

  // Captive-portal provisioning: Wi-Fi + bridge host/port/instance. On first
  // boot (or forceSetup) join AP "LocoLens-Setup" to enter them from a phone.
  WiFiManager wm;
  char portStr[8]; snprintf(portStr, sizeof(portStr), "%d", g_port);
  WiFiManagerParameter pHost("host", "Bridge host/IP", g_host, sizeof(g_host) - 1);
  WiFiManagerParameter pPort("port", "Bridge port", portStr, 6);
  WiFiManagerParameter pInst("inst", "Instance id", g_instance, sizeof(g_instance) - 1);
  wm.addParameter(&pHost); wm.addParameter(&pPort); wm.addParameter(&pInst);
  wm.setConfigPortalTimeout(300);
  wm.setAPCallback([](WiFiManager*) { banner("SETUP", "join 'LocoLens-Setup'"); });
  wm.setSaveParamsCallback([&]() {
    strncpy(g_host, pHost.getValue(), sizeof(g_host) - 1);
    strncpy(g_instance, pInst.getValue(), sizeof(g_instance) - 1);
    g_port = atoi(pPort.getValue());
    prefs.begin("locolens", false);
    prefs.putString("host", g_host); prefs.putInt("port", g_port); prefs.putString("inst", g_instance);
    prefs.end();
  });

  banner("connecting", "Wi-Fi...");
  bool ok = forceSetup ? wm.startConfigPortal("LocoLens-Setup") : wm.autoConnect("LocoLens-Setup");
  if (!ok) { banner("Wi-Fi failed", "rebooting"); delay(1500); ESP.restart(); }

  banner("connected", g_host);
  String path = String("/ws/lens/") + g_instance;
  ws.begin(g_host, g_port, path);
  ws.onEvent(onWs);
  ws.setReconnectInterval(3000);
}

void loop() {
  ws.loop();
  pollInput();
  uint32_t now = millis();
  if (connected && now - lastPing > LENS_PING_MS) {
    JsonDocument d; d["type"]="watch.ping"; sendJson(d); lastPing = now;
  }
}
