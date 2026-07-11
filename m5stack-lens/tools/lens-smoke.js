#!/usr/bin/env node
// ============================================================================
// lens-smoke.js — headless stand-in for the M5Stack watch. Proves the lens
// bridge end-to-end before (or without) the physical device:
//   * opens ws://<host>:<port>/ws/lens/<instanceId>
//   * sends the watch.hello handshake
//   * receives binary lens frames, verifies they decode (PNG/JPEG/raw), and
//     saves the first few to disk
//   * exercises every control message the watch sends and confirms the server
//     accepts them (instance.active / no error)
//
//   node lens-smoke.js [--host localhost] [--port 3001] [--instance instance-0]
//                      [--out ./lens-smoke-out] [--seconds 12]
// ============================================================================
const fs = require('fs');
const path = require('path');
const WebSocket = require('ws');

function arg(name, def) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : def;
}

const HOST = arg('host', 'localhost');
const PORT = parseInt(arg('port', '3001'), 10);
const INSTANCE = arg('instance', 'instance-0');
const OUT = path.resolve(arg('out', './lens-smoke-out'));
const SECONDS = parseInt(arg('seconds', '12'), 10);
fs.mkdirSync(OUT, { recursive: true });

const url = `ws://${HOST}:${PORT}/ws/lens/${encodeURIComponent(INSTANCE)}`;
console.log(`[smoke] connecting ${url}`);
const ws = new WebSocket(url);

const stats = { frames: 0, png: 0, jpeg: 0, raw: 0, other: 0, saved: 0, controlAcks: 0, errors: 0 };
let firstFrameAt = 0;

function sniff(buf) {
  if (buf.length > 8 && buf[0] === 0x89 && buf[1] === 0x50) return 'png';       // \x89PNG
  if (buf.length > 3 && buf[0] === 0xff && buf[1] === 0xd8) return 'jpeg';       // JPEG SOI
  if (buf.length > 4 && buf.slice(8, 12).toString() === 'RGBA') return 'raw';    // our raw header
  return 'other';
}

ws.on('open', () => {
  console.log('[smoke] open — sending watch.hello');
  ws.send(JSON.stringify({ type: 'watch.hello', watchId: 'smoke-client', fw: 'smoke/0.1' }));

  // Exercise the control surface on a schedule.
  const controls = [
    { type: 'lens.move', dx: 0.05, dy: -0.03 },
    { type: 'lens.zoom', delta: 0.3 },
    { type: 'lens.pointer', x: 0.5, y: 0.5, buttons: 0 },
    { type: 'lens.inspect' },
    { type: 'mouse.button', button: 'right', state: 'click' },
    { type: 'lens.close' },
    { type: 'watch.ping' },
  ];
  controls.forEach((c, i) => setTimeout(() => {
    ws.send(JSON.stringify(c));
    console.log(`[smoke] -> ${c.type}`);
  }, 1500 + i * 900));
});

ws.on('message', (data, isBinary) => {
  // ws v8 always delivers a Buffer; `isBinary` distinguishes lens frames
  // (binary) from JSON control replies like instance.active (text).
  if (isBinary) {
    const buf = Buffer.isBuffer(data) ? data : Buffer.from(data);
    const kind = sniff(buf);
    stats.frames++; stats[kind] = (stats[kind] || 0) + 1;
    if (!firstFrameAt) { firstFrameAt = Date.now(); console.log(`[smoke] first frame: ${kind}, ${buf.length}B`); }
    if (stats.saved < 3 && (kind === 'png' || kind === 'jpeg')) {
      const f = path.join(OUT, `lens-frame-${stats.saved}.${kind}`);
      fs.writeFileSync(f, buf); stats.saved++;
      console.log(`[smoke] saved ${f}`);
    }
  } else {
    let msg; try { msg = JSON.parse(data.toString()); } catch { return; }
    if (msg.type === 'instance.active') { stats.controlAcks++; console.log(`[smoke] <- instance.active ${msg.id}`); }
    else if (msg.type === 'error') { stats.errors++; console.log(`[smoke] <- ERROR ${msg.error}`); }
    else console.log(`[smoke] <- ${msg.type}`);
  }
});

ws.on('error', (e) => { console.error('[smoke] ws error:', e.message); });
ws.on('close', () => report());

setTimeout(() => ws.close(), SECONDS * 1000);

function report() {
  console.log('\n===== LENS SMOKE REPORT =====');
  console.log(`instance:        ${INSTANCE}`);
  console.log(`frames received: ${stats.frames}  (png=${stats.png} jpeg=${stats.jpeg} raw=${stats.raw} other=${stats.other})`);
  console.log(`frames saved:    ${stats.saved} -> ${OUT}`);
  console.log(`instance.active: ${stats.controlAcks}   server errors: ${stats.errors}`);
  const ok = stats.frames > 0 && stats.errors === 0;
  console.log(`RESULT:          ${ok ? 'PASS — lens streams frames and accepts control' : 'FAIL — no frames or server errors'}`);
  process.exit(ok ? 0 : 1);
}
