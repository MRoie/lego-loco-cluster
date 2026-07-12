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
static int g_rot = 0;   // display rotation (0 = upright on the StopWatch; recalibrate by holding KEYA at boot)

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
// On-display diagnostic + rotation calibrator (serial/HWCDC yields nothing on
// this board, so the display must self-report). Renders a numbered 4x4 grid +
// detected board id + current rotation + reported W×H, drawn redundantly so at
// least one copy is visible regardless of any panel offset/geometry bug.
// A photo tells us: which board M5GFX detected (30 == StopWatch), the panel
// size it configured, and exactly which framebuffer region is visible. Reached
// by holding KEYA at boot; KEYB cycles rotation, KEYA accepts (see setup()).
// ---------------------------------------------------------------------------
static void drawDiagGrid() {
  const int w = M5.Display.width(), h = M5.Display.height();
  const int cw = w / 4, ch = h / 4;
  static const uint16_t pal[4] = { TFT_RED, TFT_GREEN, TFT_BLUE, TFT_YELLOW };
  M5.Display.fillScreen(TFT_BLACK);
  M5.Display.setTextDatum(middle_center);
  for (int r = 0; r < 4; r++) {
    for (int c = 0; c < 4; c++) {
      int n = r * 4 + c;
      M5.Display.fillRect(c * cw + 2, r * ch + 2, cw - 4, ch - 4, pal[n & 3]);
      M5.Display.setTextColor(TFT_BLACK);
      M5.Display.setTextSize(2);
      M5.Display.drawString(String(n), c * cw + cw / 2, r * ch + ch / 2);
    }
  }
  // Full-frame border: shows where M5GFX thinks the panel edges are.
  M5.Display.drawRect(0, 0, w, h, TFT_WHITE);
  M5.Display.drawRect(1, 1, w - 2, h - 2, TFT_WHITE);
  // Detected board + size, drawn in center and all four quadrant centers so a
  // copy survives whatever region is actually visible.
  char info[48];
  snprintf(info, sizeof(info), "b%d r%d %dx%d", (int)M5.Display.getBoard(), g_rot, w, h);
  M5.Display.setTextColor(TFT_WHITE, TFT_BLACK);
  M5.Display.setTextSize(2);
  const int xs[5] = { w/2, w/4, 3*w/4, w/4, 3*w/4 };
  const int ys[5] = { h/2, h/4, h/4, 3*h/4, 3*h/4 };
  for (int i = 0; i < 5; i++) M5.Display.drawString(info, xs[i], ys[i]);
}

// ---------------------------------------------------------------------------
// Lens frame → round display (M5GFX decodes PNG/JPEG and honours alpha)
// ---------------------------------------------------------------------------
static void drawLensFrame(const uint8_t* data, size_t len) {
  if (len < 4) return;
  const int w = M5.Display.width(), h = M5.Display.height();

  // scale_x = 0.0 tells M5GFX to auto-fit the image to maxWidth/maxHeight (the
  // full panel), centred via datum middle_center. This fills the round display
  // regardless of the server's crop size. No per-frame clear: the scaled frame
  // covers the whole square each time, so there's nothing stale to flash; the
  // transparent corners fall outside the round bezel and are never seen.
  if (data[0] == 0x89 && data[1] == 0x50)                       // PNG
    M5.Display.drawPng(data, len, w / 2, h / 2, w, h, 0, 0, 0.0f, 0.0f, datum_t::middle_center);
  else if (data[0] == 0xFF && data[1] == 0xD8)                  // JPEG
    M5.Display.drawJpg(data, len, w / 2, h / 2, w, h, 0, 0, 0.0f, 0.0f, datum_t::middle_center);
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
  // M5GFX detects the M5StopWatch by probing I2C on GPIO47/48 for the
  // CST820 touch + BMI270 IMU + RX8130 RTC.  It then handles all IOE
  // (M5IOE1_G8) power sequencing internally before initialising the CO5300.
  // fallback_board ensures M5Unified uses the correct pin-map if for any
  // reason the GPIO probe returns a different board type.
  cfg.fallback_board = m5::board_t::board_M5StopWatch;
  M5.begin(cfg);                               // display + touch + buttons + power

  // Load persisted settings (rotation + bridge) before drawing anything.
  prefs.begin("locolens", true);
  g_rot  = prefs.getInt("rot", g_rot);
  g_port = prefs.getInt("port", g_port);
  prefs.getString("host", g_host, sizeof(g_host));
  prefs.getString("inst", g_instance, sizeof(g_instance));
  prefs.end();

  M5.Display.setRotation(g_rot);
  M5.Display.setBrightness(160);
  M5.Display.setTextSize(M5.Display.height() / 200);
  M5.update();

  // Hold KEYA at boot for full setup: rotation calibration + Wi-Fi re-provision.
  bool forceSetup = M5.BtnA.isPressed();

  if (forceSetup) {
    // Rotation calibration: KEYB cycles 0->1->2->3 (on-screen "rN"); KEYA accepts.
    // Serial/HWCDC yields nothing on this board, so the display self-reports.
    drawDiagGrid();
    for (;;) {
      M5.update();
      if (M5.BtnB.wasPressed()) { g_rot = (g_rot + 1) & 3; M5.Display.setRotation(g_rot); drawDiagGrid(); }
      if (M5.BtnA.wasPressed()) break;
      delay(20);
    }
    prefs.begin("locolens", false); prefs.putInt("rot", g_rot); prefs.end();
    while (M5.BtnA.isPressed()) { M5.update(); delay(20); }   // wait for release
  }

  banner("LOCO LENS");
  delay(400);
  M5.update();

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

  // Diagnostic: log display size over USB-CDC so we can verify the panel
  // is detected correctly (should be 466×466 for the M5StopWatch C152).
  Serial.printf("[LocoLens] display %dx%d  host=%s port=%d inst=%s\n",
                M5.Display.width(), M5.Display.height(), g_host, g_port, g_instance);

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
