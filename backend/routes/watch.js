/**
 * watch.js — HTTP + WebSocket surface for the Loco Lens watch link.
 *
 * REST (dashboard side):
 *   POST /api/watch/pair   { instanceId } -> { code }   issue a pairing code
 *   GET  /api/watch/status                -> paired watches + lens stats
 *
 * WebSocket (watch side): attachLensWs(server) mounts /ws/lens/:instanceId.
 * Each connection creates an RfbFramebuffer to that instance's VNC and a
 * LensBridge that streams circular crops and injects control input.
 *
 * instanceResolver(instanceId) -> { host, port, password } | null lets the
 * caller map an instance id to its VNC endpoint (k8s pod IP / compose host).
 */

const RfbFramebuffer = require('../services/rfbFramebuffer');
const LensBridge = require('../services/lensBridge');
const watchPairing = require('../services/watchPairing');
const { parseWatchMessage } = require('../protocol/watchProtocol');
const logger = require('../utils/logger');

const crypto = require('crypto');

// Crypto-strength 6-char pairing code (unambiguous alphabet, no 0/O/1/I).
function defaultCodeGen() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let out = '';
  for (const b of crypto.randomBytes(6)) out += alphabet[b % alphabet.length];
  return out;
}

function registerWatchRoutes(app, { generateCode } = {}) {
  const codeGen = generateCode || defaultCodeGen;

  app.post('/api/watch/pair', (req, res) => {
    const instanceId = req.body && req.body.instanceId;
    if (!instanceId) return res.status(400).json({ error: 'instanceId required' });
    const code = watchPairing.issueCode(codeGen(), instanceId);
    res.json({ code, instanceId });
  });

  app.get('/api/watch/status', (req, res) => {
    res.json({
      pairedWatches: watchPairing.watches.size,
      openLenses: openBridges.size,
      lensStats: [...openBridges.values()].map((b) => b.stats),
    });
  });
}

const openBridges = new Set();

/**
 * Handle one lens WebSocket connection. `instanceResolver` may be sync or
 * async and returns { host, port, password } | null for the instance's VNC.
 */
async function handleLensConnection(ws, instanceId, instanceResolver, deps = {}) {
  // Injectable for tests; defaults to the real classes.
  const Fb = deps.RfbFramebuffer || RfbFramebuffer;
  const Bridge = deps.LensBridge || LensBridge;

  let current = { id: instanceId, fb: null, bridge: null };

  // (Re)point the lens at an instance. Tears down any existing RFB+bridge and
  // connects a fresh one — used both at connect time and on instance.select.
  async function connectTo(id) {
    let endpoint = null;
    try {
      endpoint = instanceResolver ? await instanceResolver(id) : null;
    } catch (e) {
      logger.warn('Lens endpoint resolve failed', { instanceId: id, error: e.message });
    }
    if (!endpoint || !endpoint.host) {
      if (ws.readyState === ws.OPEN) {
        ws.send(JSON.stringify({ type: 'error', error: `no VNC endpoint for ${id}` }));
      }
      return false;
    }

    // Tear down the previous target.
    if (current.bridge) { current.bridge.stop(); openBridges.delete(current.bridge); }
    if (current.fb) current.fb.close();

    const fb = new Fb(endpoint);
    try { fb.connect(); } catch (e) {
      logger.warn('Lens RFB connect failed', { instanceId: id, error: e.message });
    }
    const bridge = new Bridge({
      framebuffer: fb,
      send: (data) => { if (ws.readyState === ws.OPEN) ws.send(data); },
      size: parseInt(process.env.LENS_CROP_SIZE, 10) || 466,
    });
    bridge.start();
    openBridges.add(bridge);
    current = { id, fb, bridge };
    if (ws.readyState === ws.OPEN) {
      ws.send(JSON.stringify({ type: 'instance.active', id }));
    }
    logger.info('Lens pointed at instance', { instanceId: id });
    return true;
  }

  const ok = await connectTo(instanceId);
  if (!ok) { ws.close(); return; }

  ws.on('message', async (data) => {
    const res = parseWatchMessage(data.toString());
    if (res.ok && res.msg.type === 'instance.select') {
      // Actually re-point the lens at the newly selected instance.
      const switched = await connectTo(res.msg.id);
      if (!switched) logger.warn('instance.select failed', { from: current.id, to: res.msg.id });
      return; // handled here; don't forward to the (possibly replaced) bridge
    }
    if (current.bridge) current.bridge.handleMessage(data.toString());
  });

  ws.on('close', () => {
    if (current.bridge) { current.bridge.stop(); openBridges.delete(current.bridge); }
    if (current.fb) current.fb.close();
    logger.info('Lens connection closed', { instanceId: current.id });
  });
}

module.exports = { registerWatchRoutes, handleLensConnection, openBridges };
