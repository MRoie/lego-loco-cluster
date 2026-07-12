/**
 * rfbFramebuffer.js — maintain a live RGB framebuffer for one QEMU instance
 * by connecting to its VNC/RFB endpoint (via the existing `rfb2` dependency).
 *
 * The lens bridge reads whole frames from here without any OCR: RFB delivers
 * raw rectangle updates which we blit into a persistent framebuffer. Pointer
 * and key events are injected back through the same RFB connection so the
 * stream and the input provably target the same guest.
 */

const logger = require('../utils/logger');

class RfbFramebuffer {
  /**
   * @param {object} opts
   * @param {string} opts.host   VNC host
   * @param {number} opts.port   VNC port (e.g. 5901)
   * @param {string} [opts.password]
   * @param {function} [opts.rfbFactory] injectable rfb2 client factory (tests)
   */
  constructor({ host, port, password, rfbFactory } = {}) {
    this.host = host;
    this.port = port;
    this.password = password;
    this.rfbFactory = rfbFactory || null;

    this.width = 0;
    this.height = 0;
    this.channels = 3;
    this.pixels = null;       // Buffer, row-major RGB
    this.lastFrameAt = 0;     // ms timestamp of last update (Date.now via injectable clock)
    this.connected = false;
    this.client = null;
    this._now = () => Date.now();
  }

  /** Allow tests / resume-safe callers to supply a clock. */
  setClock(fn) { this._now = fn; }

  connect() {
    const factory = this.rfbFactory || (() => require('rfb2').createConnection({
      host: this.host, port: this.port, password: this.password,
    }));
    this.client = factory();

    this.client.on('connect', () => {
      this.width = this.client.width;
      this.height = this.client.height;
      this.pixels = Buffer.alloc(this.width * this.height * this.channels);
      this.connected = true;
      logger.info('RFB framebuffer connected', { host: this.host, port: this.port, w: this.width, h: this.height });
      this.client.requestUpdate(false, 0, 0, this.width, this.height);
      // Periodically request a full update so the lens bridge always has a
      // recent frame even when the Win98 guest is idle (no screen changes).
      this._refreshTimer = setInterval(() => {
        if (this.connected && this.client && this.client.requestUpdate) {
          this.client.requestUpdate(false, 0, 0, this.width, this.height);
        }
      }, 500);
    });

    this.client.on('rect', (rect) => {
      this._blit(rect);
      this.lastFrameAt = this._now();
      // Ask for the next incremental update.
      if (this.client.requestUpdate) {
        this.client.requestUpdate(true, 0, 0, this.width, this.height);
      }
    });

    this.client.on('error', (err) => {
      logger.warn('RFB framebuffer error', { host: this.host, port: this.port, error: err && err.message });
      this.connected = false;
    });

    this.client.on('close', () => { this.connected = false; });
    return this;
  }

  /** Blit an RFB raw rectangle (RGB or 32-bit) into the framebuffer. */
  _blit(rect) {
    if (!this.pixels || !rect || !rect.data) return;
    const { x, y, width, height } = rect;
    const srcChannels = rect.data.length >= width * height * 4 ? 4 : 3;
    for (let ry = 0; ry < height; ry++) {
      const dyRow = (y + ry) * this.width;
      for (let rx = 0; rx < width; rx++) {
        const si = (ry * width + rx) * srcChannels;
        const di = (dyRow + (x + rx)) * this.channels;
        if (di + 2 >= this.pixels.length) continue;
        this.pixels[di] = rect.data[si];
        this.pixels[di + 1] = rect.data[si + 1];
        this.pixels[di + 2] = rect.data[si + 2];
      }
    }
  }

  /** Current frame + metadata (or null before first update). */
  getFrame() {
    if (!this.pixels) return null;
    return {
      width: this.width,
      height: this.height,
      channels: this.channels,
      pixels: this.pixels,
      ageMs: this._now() - this.lastFrameAt,
    };
  }

  /** Inject an absolute pointer event; x,y normalized [0,1], buttons bitmask. */
  sendPointer(xNorm, yNorm, buttons) {
    if (!this.connected || !this.client || !this.client.pointerEvent) return false;
    const px = Math.round(Math.min(1, Math.max(0, xNorm)) * (this.width - 1));
    const py = Math.round(Math.min(1, Math.max(0, yNorm)) * (this.height - 1));
    this.client.pointerEvent(px, py, buttons & 0x7);
    return true;
  }

  /** Inject a key event (RFB keysym, down/up). */
  sendKey(keysym, isDown) {
    if (!this.connected || !this.client || !this.client.keyEvent) return false;
    this.client.keyEvent(keysym, isDown ? 1 : 0);
    return true;
  }

  close() {
    if (this._refreshTimer) { clearInterval(this._refreshTimer); this._refreshTimer = null; }
    if (this.client && this.client.end) { try { this.client.end(); } catch (e) { /* ignore */ } }
    this.connected = false;
  }
}

module.exports = RfbFramebuffer;
