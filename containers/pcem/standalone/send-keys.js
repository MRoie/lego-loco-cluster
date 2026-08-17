// Usage: node send-keys.js <vnc-port> <comma,separated,hex,keysyms> [holdMs] [gapMs]
// IMPORTANT: the target SDL window (PCem, or any SDL-based emulator) must have
// its mouse "captured" first — see README.md gotcha #8 — otherwise keys are
// silently dropped/delayed. sendKey() also silently no-ops if called before
// the RFB connection is actually established, which is why this waits for
// fb.connected rather than using a blind setTimeout.
const path = require("path");
const RfbFramebuffer = require(path.resolve(__dirname, "../../../backend/services/rfbFramebuffer"));

const port = parseInt(process.argv[2], 10);
const keys = process.argv[3].split(",").map(Number);
const delay = parseInt(process.argv[4] || "150", 10);
const gap = parseInt(process.argv[5] || "600", 10);

const fb = new RfbFramebuffer({ host: "127.0.0.1", port });
fb.connect();

function tap(k, cb) {
  const ok1 = fb.sendKey(k, true);
  setTimeout(() => {
    const ok2 = fb.sendKey(k, false);
    console.log(`key 0x${k.toString(16)} down=${ok1} up=${ok2}`);
    cb && cb();
  }, delay);
}

function sendAll(i) {
  if (i >= keys.length) { console.log("ALL_KEYS_SENT"); setTimeout(() => process.exit(0), 500); return; }
  tap(keys[i], () => setTimeout(() => sendAll(i + 1), gap));
}

// Wait for the ACTUAL connect event instead of a blind timeout — sendKey()
// silently no-ops (returns false) if called before fb.connected is true.
function waitForConnection() {
  if (fb.connected) { sendAll(0); return; }
  setTimeout(waitForConnection, 100);
}
waitForConnection();

setTimeout(() => { console.log("TIMEOUT_NEVER_CONNECTED"); process.exit(1); }, 15000);
