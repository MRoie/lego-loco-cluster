// ============================================================================
// Loco Lens — M5Stack StopWatch firmware
// ============================================================================
// A synchronized second-screen controller for a running Lego Loco instance.
// The round display shows a circular crop of the real game framebuffer,
// streamed from the backend lens bridge over WebSocket; touch and buttons are
// sent back as normalized control messages that the bridge injects into the
// guest via RFB. The watch never speaks RFB itself.
//
// Protocol (see backend/protocol/watchProtocol.js) — all coords normalized:
//   send  {type:"lens.move",  dx,dy}      drag the lens
//         {type:"lens.pointer", x,y,buttons}
//         {type:"lens.inspect"}           tap → inspect object under centre
//         {type:"lens.close"}             long-press → close inspection
//         {type:"lens.zoom",  delta}      buttons → zoom in/out
//         {type:"mouse.button", button, state}
//         {type:"watch.ping"}             keepalive
//   recv  binary PNG lens frame (bridge default) → decode + blit
// ============================================================================
#include <Arduino.h>
#include <WiFi.h>
#include <WebSocketsClient.h>
#include <ArduinoJson.h>
#include <PNGdec.h>
#include <TFT_eSPI.h>
#include "config.h"

static TFT_eSPI tft = TFT_eSPI();
static WebSocketsClient ws;
static PNG png;
static uint32_t lastPing = 0;
static bool connected = false;

// ---- Touch state (drives lens.move / lens.inspect / lens.close) ----
struct Touch { bool down=false; uint32_t t0=0; int x0=0,y0=0,lastX=0,lastY=0; } touch;

// ---------------------------------------------------------------------------
// PNG frame → round display
// ---------------------------------------------------------------------------
static int pngXOffset = 0, pngYOffset = 0;
static void pngDraw(PNGDRAW *pDraw) {
  uint16_t line[LENS_DISPLAY_W];
  png.getLineAsRGB565(pDraw, line, PNG_RGB565_BIG_ENDIAN, 0xffffffff);
  // The bridge already masks corners transparent; we just center-blit,
  // downscaling the square crop to the panel width by nearest-neighbour.
  int srcW = pDraw->iWidth;
  float sx = (float)srcW / LENS_DISPLAY_W;
  if (pDraw->y % (int)ceilf(sx) != 0) return; // cheap vertical decimation
  int dy = (int)(pDraw->y / sx);
  if (dy >= LENS_DISPLAY_H) return;
  uint16_t row[LENS_DISPLAY_W];
  for (int dx = 0; dx < LENS_DISPLAY_W; dx++) row[dx] = line[(int)(dx * sx)];
  tft.pushImage(0, dy, LENS_DISPLAY_W, 1, row);
}

static void onLensFrame(uint8_t *data, size_t len) {
  int rc = png.openRAM(data, len, pngDraw);
  if (rc == PNG_SUCCESS) { png.decode(nullptr, 0); png.close(); }
}

// ---------------------------------------------------------------------------
// Control messages
// ---------------------------------------------------------------------------
static void sendJson(const JsonDocument &doc) {
  String out; serializeJson(doc, out); ws.sendTXT(out);
}
static void sendMove(float dx, float dy) {
  JsonDocument d; d["type"]="lens.move"; d["dx"]=dx; d["dy"]=dy; sendJson(d);
}
static void sendInspect() { JsonDocument d; d["type"]="lens.inspect"; sendJson(d); }
static void sendClose()   { JsonDocument d; d["type"]="lens.close";   sendJson(d); }
static void sendZoom(float delta) { JsonDocument d; d["type"]="lens.zoom"; d["delta"]=delta; sendJson(d); }

// ---------------------------------------------------------------------------
// WebSocket events
// ---------------------------------------------------------------------------
static void onWsEvent(WStype_t type, uint8_t *payload, size_t length) {
  switch (type) {
    case WStype_CONNECTED:
      connected = true;
      tft.fillScreen(TFT_BLACK);
      { JsonDocument d; d["type"]="watch.hello"; d["watchId"]=WiFi.macAddress();
        d["fw"]=LOCO_LENS_FW_VERSION; sendJson(d); }
      break;
    case WStype_DISCONNECTED:
      connected = false; break;
    case WStype_BIN:
      onLensFrame(payload, length); break;
    default: break;
  }
}

// ---------------------------------------------------------------------------
// Input (touch drag → move; tap → inspect; long-press → close; buttons → zoom)
// ---------------------------------------------------------------------------
static bool readTouch(int &x, int &y) {
  uint16_t tx, ty;
  if (tft.getTouch(&tx, &ty)) { x = tx; y = ty; return true; }
  return false;
}

static void pollInput() {
  int x, y; bool now = readTouch(x, y);
  uint32_t t = millis();
  if (now && !touch.down) {                       // press
    touch = { true, t, x, y, x, y };
  } else if (now && touch.down) {                 // drag → lens.move
    float dx = (x - touch.lastX) / (float)LENS_DISPLAY_W * LENS_MOVE_GAIN;
    float dy = (y - touch.lastY) / (float)LENS_DISPLAY_H * LENS_MOVE_GAIN;
    if (fabsf(dx) > 0.002f || fabsf(dy) > 0.002f) { sendMove(dx, dy); touch.lastX=x; touch.lastY=y; }
  } else if (!now && touch.down) {                // release
    uint32_t held = t - touch.t0;
    int moved = abs(x - touch.x0) + abs(y - touch.y0);
    if (held >= LENS_LONGPRESS_MS)      sendClose();
    else if (held <= LENS_TAP_MS && moved < 8) sendInspect();
    touch.down = false;
  }

  // Side buttons: BOOT(0) zoom out, and GPIO14 zoom in (adjust per board).
  static bool p0 = true, p14 = true;
  bool b0 = digitalRead(0), b14 = digitalRead(14);
  if (!b0 && p0) sendZoom(-0.25f);
  if (!b14 && p14) sendZoom(0.25f);
  p0 = b0; p14 = b14;
}

// ---------------------------------------------------------------------------
void setup() {
  Serial.begin(115200);
  pinMode(0, INPUT_PULLUP); pinMode(14, INPUT_PULLUP);
  tft.init(); tft.setRotation(0); tft.fillScreen(TFT_BLACK);
  tft.setTextColor(TFT_YELLOW); tft.drawCentreString("LOCO LENS", LENS_DISPLAY_W/2, LENS_DISPLAY_H/2 - 10, 2);

  WiFi.begin(LOCO_WIFI_SSID, LOCO_WIFI_PASS);
  uint32_t t0 = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - t0 < 20000) { delay(250); }

  String path = String("/ws/lens/") + LOCO_INSTANCE_ID;
  ws.begin(LOCO_BRIDGE_HOST, LOCO_BRIDGE_PORT, path);
  ws.onEvent(onWsEvent);
  ws.setReconnectInterval(3000);
}

void loop() {
  ws.loop();
  pollInput();
  uint32_t t = millis();
  if (connected && t - lastPing > LENS_PING_MS) {
    JsonDocument d; d["type"]="watch.ping"; sendJson(d); lastPing = t;
  }
}
