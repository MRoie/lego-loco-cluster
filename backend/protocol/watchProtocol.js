/**
 * watchProtocol.js — message schema for the M5Stack "Loco Lens" watch link.
 *
 * The watch never speaks RFB. It exchanges small JSON control messages with
 * the lens bridge over `/ws/lens/:instanceId`; the bridge translates them
 * into RFB pointer/keyboard events against the running QEMU instance.
 *
 * All spatial coordinates are NORMALIZED to [0,1] relative to the framebuffer
 * so the same messages work regardless of guest resolution (800x600, 1024x768).
 */

const MESSAGE_TYPES = Object.freeze([
  'lens.move',       // relative nudge of the lens centre: {dx, dy} in [-1,1]
  'lens.pointer',    // absolute pointer + buttons: {x, y in [0,1], buttons bitmask}
  'lens.inspect',    // tap → inspect object under the lens centre
  'lens.close',      // long press → close inspection
  'lens.zoom',       // {delta} in [-1,1]; +in / -out
  'instance.select', // switch active instance: {id}
  'mouse.button',    // {button: left|middle|right, state: down|up|click}
  'watch.hello',     // pairing handshake: {watchId, fw}
  'watch.ping',      // keepalive
]);

const BUTTON_BITS = Object.freeze({ left: 1, middle: 2, right: 4 });

function clamp(v, lo, hi) {
  if (typeof v !== 'number' || Number.isNaN(v)) return lo;
  return Math.min(hi, Math.max(lo, v));
}

/**
 * Validate and normalize an inbound watch message.
 * @param {*} raw - parsed JSON object (or a JSON string)
 * @returns {{ok: true, msg: object} | {ok: false, error: string}}
 */
function parseWatchMessage(raw) {
  let obj = raw;
  if (typeof raw === 'string') {
    try { obj = JSON.parse(raw); }
    catch (e) { return { ok: false, error: 'invalid JSON' }; }
  }
  if (!obj || typeof obj !== 'object') return { ok: false, error: 'not an object' };
  const { type } = obj;
  if (!MESSAGE_TYPES.includes(type)) return { ok: false, error: `unknown type: ${type}` };

  switch (type) {
    case 'lens.move':
      return { ok: true, msg: { type, dx: clamp(obj.dx, -1, 1), dy: clamp(obj.dy, -1, 1) } };
    case 'lens.pointer':
      return {
        ok: true,
        msg: {
          type,
          x: clamp(obj.x, 0, 1),
          y: clamp(obj.y, 0, 1),
          buttons: Number.isInteger(obj.buttons) ? (obj.buttons & 0x7) : 0,
        },
      };
    case 'lens.zoom':
      return { ok: true, msg: { type, delta: clamp(obj.delta, -1, 1) } };
    case 'instance.select':
      if (typeof obj.id !== 'string' || !obj.id) return { ok: false, error: 'instance.select needs id' };
      return { ok: true, msg: { type, id: obj.id } };
    case 'mouse.button': {
      const button = ['left', 'middle', 'right'].includes(obj.button) ? obj.button : 'left';
      const state = ['down', 'up', 'click'].includes(obj.state) ? obj.state : 'click';
      return { ok: true, msg: { type, button, state } };
    }
    case 'watch.hello':
      return { ok: true, msg: { type, watchId: String(obj.watchId || ''), fw: String(obj.fw || '') } };
    case 'lens.inspect':
    case 'lens.close':
    case 'watch.ping':
      return { ok: true, msg: { type } };
    default:
      return { ok: false, error: `unhandled type: ${type}` };
  }
}

/**
 * Whether a message is control (priority over frame delivery). Control
 * messages must never be dropped or queued behind stale lens frames.
 */
function isControlMessage(type) {
  return type !== 'watch.ping' && type !== 'watch.hello';
}

module.exports = { MESSAGE_TYPES, BUTTON_BITS, parseWatchMessage, isControlMessage, clamp };
