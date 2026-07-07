/**
 * watchPairing.js — minimal pairing registry for M5Stack watches.
 *
 * A watch presents a short pairing code (shown in the dashboard) on connect.
 * This keeps a watch↔instance binding and the current active instance so the
 * watch can drive whichever instance the dashboard has focused, reusing the
 * existing active-instance concept rather than inventing a second focus system.
 */

class WatchPairing {
  constructor() {
    this.codes = new Map();   // code -> { instanceId, createdAt }
    this.watches = new Map(); // watchId -> { instanceId, pairedAt }
  }

  /** Issue a pairing code bound to an instance (dashboard-initiated). */
  issueCode(code, instanceId, now = Date.now()) {
    this.codes.set(code, { instanceId, createdAt: now });
    return code;
  }

  /** A watch redeems a code → returns the bound instanceId or null. */
  redeem(code, watchId, now = Date.now()) {
    const entry = this.codes.get(code);
    if (!entry) return null;
    this.codes.delete(code);
    this.watches.set(watchId, { instanceId: entry.instanceId, pairedAt: now });
    return entry.instanceId;
  }

  /** Re-target a paired watch to a different instance (instance.select). */
  retarget(watchId, instanceId) {
    const w = this.watches.get(watchId);
    if (!w) return false;
    w.instanceId = instanceId;
    return true;
  }

  getInstanceFor(watchId) {
    const w = this.watches.get(watchId);
    return w ? w.instanceId : null;
  }

  unpair(watchId) { return this.watches.delete(watchId); }
}

module.exports = new WatchPairing();
module.exports.WatchPairing = WatchPairing;
