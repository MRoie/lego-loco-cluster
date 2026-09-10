#include <M5Unified.h>
#include <WiFi.h>
#include <WiFiManager.h>
#include <Preferences.h>
#include <WebSocketsClient.h>
#include <ArduinoJson.h>
#include <Wire.h>

static WebSocketsClient ws;
static Preferences prefs;
static bool wsConnected = false;
static bool frameRequested = false;
static uint32_t lastRequestAt = 0;
static uint32_t lastPingAt = 0;

static char gHost[64] = "192.168.1.50";
static int gPort = 3002;
static char gInstance[32] = "instance-0";
static int gInstanceCount = 9;
static int gInstanceIndex = 0;

// PaperColor Port A pins in current M5Unified board table.
static constexpr int I2C_SDA = 2;
static constexpr int I2C_SCL = 3;

// Optional GT911 touch overlay. Both common addresses are supported.
static uint8_t gtAddr = 0;
static bool touchDown = false;
static int lastTouchX = 0;
static int lastTouchY = 0;

static void sendJson(const JsonDocument& d) {
  if (!wsConnected) return;
  String out;
  serializeJson(d, out);
  ws.sendTXT(out);
}

static void requestFrame() {
  if (!wsConnected || frameRequested) return;
  JsonDocument d;
  d["type"] = "frame.request";
  sendJson(d);
  frameRequested = true;
  lastRequestAt = millis();
}

static void sendPointer(float x, float y, int buttons = 0) {
  JsonDocument d;
  d["type"] = "pointer";
  d["x"] = constrain(x, 0.0f, 1.0f);
  d["y"] = constrain(y, 0.0f, 1.0f);
  d["buttons"] = buttons;
  sendJson(d);
}

static void sendClick(float x, float y) {
  JsonDocument d;
  d["type"] = "click";
  d["x"] = constrain(x, 0.0f, 1.0f);
  d["y"] = constrain(y, 0.0f, 1.0f);
  sendJson(d);
}

static void selectInstance(int idx) {
  if (gInstanceCount < 1) return;
  idx %= gInstanceCount;
  if (idx < 0) idx += gInstanceCount;
  gInstanceIndex = idx;

  String id = String("instance-") + idx;
  id.toCharArray(gInstance, sizeof(gInstance));

  JsonDocument d;
  d["type"] = "instance.select";
  d["id"] = gInstance;
  sendJson(d);

  frameRequested = false;
  requestFrame();
}

static bool i2cWriteReg16(uint8_t addr, uint16_t reg, uint8_t value) {
  Wire.beginTransmission(addr);
  Wire.write((uint8_t)(reg >> 8));
  Wire.write((uint8_t)(reg & 0xFF));
  Wire.write(value);
  return Wire.endTransmission() == 0;
}

static bool i2cReadReg16(uint8_t addr, uint16_t reg, uint8_t* data, size_t len) {
  Wire.beginTransmission(addr);
  Wire.write((uint8_t)(reg >> 8));
  Wire.write((uint8_t)(reg & 0xFF));
  if (Wire.endTransmission(false) != 0) return false;
  size_t got = Wire.requestFrom((int)addr, (int)len);
  if (got != len) return false;
  for (size_t i = 0; i < len; ++i) data[i] = Wire.read();
  return true;
}

static bool probeGt911() {
  const uint8_t candidates[] = {0x5D, 0x14};
  uint8_t product[4] = {};
  for (uint8_t addr : candidates) {
    if (i2cReadReg16(addr, 0x8140, product, sizeof(product))) {
      gtAddr = addr;
      return true;
    }
  }
  return false;
}

static bool readGt911(int& x, int& y, bool& pressed) {
  if (!gtAddr) return false;

  uint8_t status = 0;
  if (!i2cReadReg16(gtAddr, 0x814E, &status, 1)) return false;
  if ((status & 0x80) == 0) return true;

  const uint8_t count = status & 0x0F;
  if (count > 0) {
    uint8_t p[8] = {};
    if (i2cReadReg16(gtAddr, 0x8150, p, sizeof(p))) {
      x = p[1] | (p[2] << 8);
      y = p[3] | (p[4] << 8);
      pressed = true;
    }
  } else {
    pressed = false;
  }

  i2cWriteReg16(gtAddr, 0x814E, 0);
  return true;
}

static void drawStatus(const char* a, const char* b = nullptr) {
  M5.Display.fillScreen(TFT_WHITE);
  M5.Display.setTextColor(TFT_BLACK, TFT_WHITE);
  M5.Display.setTextDatum(middle_center);
  M5.Display.setTextSize(2);
  int cx = M5.Display.width() / 2;
  int cy = M5.Display.height() / 2;
  M5.Display.drawString(a, cx, b ? cy - 18 : cy);
  if (b) M5.Display.drawString(b, cx, cy + 18);
}

static void onWs(WStype_t type, uint8_t* payload, size_t len) {
  switch (type) {
    case WStype_CONNECTED: {
      wsConnected = true;
      frameRequested = false;
      JsonDocument d;
      d["type"] = "ping";
      d["ts"] = millis();
      sendJson(d);
      requestFrame();
      break;
    }

    case WStype_DISCONNECTED:
      wsConnected = false;
      frameRequested = false;
      drawStatus("LOCO PAPERCOLOR", "reconnecting...");
      break;

    case WStype_BIN:
      // The gateway always sends a 600x400 JPEG. drawJpg() blocks through the
      // display driver's transfer/refresh path; only after it returns do we ask
      // for a newer frame, so snapshots never queue behind the slow E Ink panel.
      if (len > 3 && payload[0] == 0xFF && payload[1] == 0xD8) {
        M5.Display.drawJpg(payload, len, 0, 0, M5.Display.width(), M5.Display.height());
      }
      frameRequested = false;
      requestFrame();
      break;

    case WStype_TEXT: {
      JsonDocument d;
      if (deserializeJson(d, payload, len) == DeserializationError::Ok) {
        const char* msgType = d["type"] | "";
        if (!strcmp(msgType, "frame.pending")) {
          frameRequested = false;
        }
      }
      break;
    }

    default:
      break;
  }
}

static void pollControls() {
  M5.update();

  if (M5.BtnA.wasPressed()) selectInstance(gInstanceIndex - 1);
  if (M5.BtnB.wasPressed()) sendClick(0.5f, 0.5f);
  if (M5.BtnC.wasPressed()) selectInstance(gInstanceIndex + 1);

  int x = 0, y = 0;
  bool pressed = false;
  if (readGt911(x, y, pressed)) {
    // Most 600x400 overlays report panel-space coordinates. Clamp here so a
    // slightly larger raw range still maps safely to the game framebuffer.
    float nx = constrain(x / 599.0f, 0.0f, 1.0f);
    float ny = constrain(y / 399.0f, 0.0f, 1.0f);

    if (pressed) {
      if (!touchDown) {
        touchDown = true;
      }
      if (abs(x - lastTouchX) + abs(y - lastTouchY) > 3) {
        sendPointer(nx, ny, 0);
        lastTouchX = x;
        lastTouchY = y;
      }
    } else if (touchDown) {
      touchDown = false;
      sendClick(constrain(lastTouchX / 599.0f, 0.0f, 1.0f),
                constrain(lastTouchY / 399.0f, 0.0f, 1.0f));
    }
  }
}

void setup() {
  auto cfg = M5.config();
  cfg.fallback_board = m5::board_t::board_M5PaperColor;
  M5.begin(cfg);
  M5.Display.setRotation(1);

  prefs.begin("locopaper", true);
  gPort = prefs.getInt("port", gPort);
  gInstanceCount = prefs.getInt("count", gInstanceCount);
  prefs.getString("host", gHost, sizeof(gHost));
  prefs.getString("inst", gInstance, sizeof(gInstance));
  prefs.end();

  if (sscanf(gInstance, "instance-%d", &gInstanceIndex) != 1) gInstanceIndex = 0;

  Wire.begin(I2C_SDA, I2C_SCL, 400000);
  bool haveTouch = probeGt911();

  drawStatus("LOCO PAPERCOLOR", haveTouch ? "GT911 touch found" : "buttons ready");

  bool forceSetup = M5.BtnA.isPressed();
  WiFiManager wm;

  char portStr[8];
  char countStr[8];
  snprintf(portStr, sizeof(portStr), "%d", gPort);
  snprintf(countStr, sizeof(countStr), "%d", gInstanceCount);

  WiFiManagerParameter pHost("host", "Gateway host/IP", gHost, sizeof(gHost) - 1);
  WiFiManagerParameter pPort("port", "Gateway port", portStr, 7);
  WiFiManagerParameter pInst("inst", "Initial instance", gInstance, sizeof(gInstance) - 1);
  WiFiManagerParameter pCount("count", "Instance count", countStr, 3);
  wm.addParameter(&pHost);
  wm.addParameter(&pPort);
  wm.addParameter(&pInst);
  wm.addParameter(&pCount);
  wm.setConfigPortalTimeout(300);

  wm.setSaveParamsCallback([&]() {
    strncpy(gHost, pHost.getValue(), sizeof(gHost) - 1);
    strncpy(gInstance, pInst.getValue(), sizeof(gInstance) - 1);
    gPort = atoi(pPort.getValue());
    gInstanceCount = max(1, atoi(pCount.getValue()));

    prefs.begin("locopaper", false);
    prefs.putString("host", gHost);
    prefs.putString("inst", gInstance);
    prefs.putInt("port", gPort);
    prefs.putInt("count", gInstanceCount);
    prefs.end();
  });

  bool ok = forceSetup ? wm.startConfigPortal("LocoPaper-Setup")
                       : wm.autoConnect("LocoPaper-Setup");
  if (!ok) {
    drawStatus("Wi-Fi failed", "restarting");
    delay(1500);
    ESP.restart();
  }

  String path = String("/ws/papercolor/") + gInstance;
  ws.begin(gHost, gPort, path);
  ws.onEvent(onWs);
  ws.setReconnectInterval(3000);
}

void loop() {
  ws.loop();
  pollControls();

  uint32_t now = millis();
  if (wsConnected && !frameRequested && now - lastRequestAt > 1000) requestFrame();

  // If a frame request gets lost, retry rather than leaving the paper frozen.
  if (wsConnected && frameRequested && now - lastRequestAt > 10000) {
    frameRequested = false;
    requestFrame();
  }

  if (wsConnected && now - lastPingAt > 30000) {
    JsonDocument d;
    d["type"] = "ping";
    d["ts"] = now;
    sendJson(d);
    lastPingAt = now;
  }

  delay(5);
}
