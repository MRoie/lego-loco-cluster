/**
 * lensBridge.js — glue between a watch WebSocket and one QEMU instance.
 *
 * Responsibilities:
 *   * hold the lens centre + zoom (updated by control messages)
 *   * pace lens frames at a target fps, DROPPING stale frames rather than
 *     queueing them (control always has priority)
 *   * translate watch control messages into RFB pointer/key injection
 *
 * The bridge does not own the RFB connection or the socket; both are injected
 * so it is unit-testable with mocks.
 */

const { parseWatchMessage } = require('../protocol/watchProtocol');
const { lensSourceRect, circularCrop, lensPointToFramebuffer } = require('./lensCrop');
const { encodeLensFrame } = require('./lensEncoder');
const logger = require('../utils/logger');

class LensBridge {
  /**
   * @param {object} opts
   * @param {object} opts.framebuffer  RfbFramebuffer-like ({getFrame, sendPointer})
   * @param {object} opts.send         function(buffer|string) to the watch
   * @param {number} [opts.fps=10]
   * @param {number} [opts.size=400]   output crop edge
   * @param {number} [opts.staleMs=250] drop frames older than this
   * @param {'png'|'jpeg'|'raw'} [opts.format='jpeg']
   */
  constructor({ framebuffer, send, fps = 10, size = 400, staleMs = 250, format = 'jpeg' }) {
    this.fb = framebuffer;
    this.send = send;
    this.intervalMs = Math.round(1000 / fps);
    this.size = size;
    this.staleMs = staleMs;
    this.format = format;

    this.cx = 0.5;
    this.cy = 0.5;
    this.zoom = 1.5;
    this._timer = null;
    this._encoding = false;
    this.stats = { sent: 0, droppedStale: 0, droppedBusy: 0, controls: 0 };
  }

  start() {
    if (this._timer) return;
    this._timer = setInterval(() => this._tick(), this.intervalMs);
  }

  stop() {
    if (this._timer) clearInterval(this._timer);
    this._timer = null;
  }

  /** Handle one inbound watch message. Returns the parsed msg or null. */
  handleMessage(raw) {
    const res = parseWatchMessage(raw);
    if (!res.ok) {
      logger.debug('Dropping invalid watch message', { error: res.error });
      return null;
    }
    const msg = res.msg;
    this.stats.controls++;

    switch (msg.type) {
      case 'lens.move':
        this.cx = clamp01(this.cx + msg.dx * 0.1);
        this.cy = clamp01(this.cy + msg.dy * 0.1);
        break;
      case 'lens.zoom':
        this.zoom = Math.min(8, Math.max(0.5, this.zoom * (1 + msg.delta * 0.25)));
        break;
      case 'lens.pointer':
      case 'mouse.button': {
        const frame = this.fb.getFrame && this.fb.getFrame();
        if (frame) {
          const rect = lensSourceRect({ fbWidth: frame.width, fbHeight: frame.height, cx: this.cx, cy: this.cy, zoom: this.zoom });
          const lensX = msg.type === 'lens.pointer' ? msg.x : 0.5;
          const lensY = msg.type === 'lens.pointer' ? msg.y : 0.5;
          const fbPt = lensPointToFramebuffer({ lensX, lensY, rect, fbWidth: frame.width, fbHeight: frame.height });
          const buttons = msg.type === 'lens.pointer' ? msg.buttons : buttonToMask(msg.button, msg.state);
          this.fb.sendPointer && this.fb.sendPointer(fbPt.x, fbPt.y, buttons);
          if (msg.type === 'mouse.button' && msg.state === 'click') {
            this.fb.sendPointer && this.fb.sendPointer(fbPt.x, fbPt.y, 0); // release
          }
        }
        break;
      }
      case 'lens.inspect': {
        // Inspect == left-click at the lens centre.
        const frame = this.fb.getFrame && this.fb.getFrame();
        if (frame) {
          const rect = lensSourceRect({ fbWidth: frame.width, fbHeight: frame.height, cx: this.cx, cy: this.cy, zoom: this.zoom });
          const fbPt = lensPointToFramebuffer({ lensX: 0.5, lensY: 0.5, rect, fbWidth: frame.width, fbHeight: frame.height });
          this.fb.sendPointer && this.fb.sendPointer(fbPt.x, fbPt.y, 1);
          this.fb.sendPointer && this.fb.sendPointer(fbPt.x, fbPt.y, 0);
        }
        break;
      }
      default:
        break; // lens.close / watch.* handled by the route layer
    }
    return msg;
  }

  /** Emit one lens frame if a fresh framebuffer is available. */
  async _tick() {
    if (this._encoding) { this.stats.droppedBusy++; return; }
    const frame = this.fb.getFrame && this.fb.getFrame();
    if (!frame) return;
    if (frame.ageMs > this.staleMs) { this.stats.droppedStale++; return; }

    this._encoding = true;
    try {
      const rect = lensSourceRect({ fbWidth: frame.width, fbHeight: frame.height, cx: this.cx, cy: this.cy, zoom: this.zoom });
      const rgba = circularCrop({
        pixels: frame.pixels, fbWidth: frame.width, fbHeight: frame.height,
        channels: frame.channels, rect, size: this.size, circular: true,
      });
      const encoded = await encodeLensFrame(rgba, { format: this.format });
      this.send(encoded.data);
      this.stats.sent++;
    } catch (e) {
      logger.warn('Lens frame encode failed', { error: e.message });
    } finally {
      this._encoding = false;
    }
  }
}

function clamp01(v) { return Math.min(1, Math.max(0, v)); }

function buttonToMask(button, state) {
  if (state === 'up') return 0;
  const bit = { left: 1, middle: 2, right: 4 }[button] || 1;
  return bit;
}

module.exports = LensBridge;
