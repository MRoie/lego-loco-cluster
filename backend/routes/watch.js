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
async function handleLensConnection(ws, instanceId, instanceResolver) {
  let endpoint = null;
  try {
    endpoint = instanceResolver ? await instanceResolver(instanceId) : null;
  } catch (e) {
    logger.warn('Lens endpoint resolve failed', { instanceId, error: e.message });
  }
  if (!endpoint || !endpoint.host) {
    if (ws.readyState === ws.OPEN) {
      ws.send(JSON.stringify({ type: 'error', error: `no VNC endpoint for ${instanceId}` }));
    }
    ws.close();
    return;
  }

  const fb = new RfbFramebuffer(endpoint);
  try { fb.connect(); } catch (e) {
    logger.warn('Lens RFB connect failed', { instanceId, error: e.message });
  }

  const bridge = new LensBridge({
    framebuffer: fb,
    send: (data) => { if (ws.readyState === ws.OPEN) ws.send(data); },
  });
  bridge.start();
  openBridges.add(bridge);
  logger.info('Lens connection opened', { instanceId });

  ws.on('message', (data) => {
    const res = parseWatchMessage(data.toString());
    if (res.ok && res.msg.type === 'instance.select') {
      // Re-target would reconnect the RFB; for the foundation we just log it.
      logger.info('Lens instance.select', { from: instanceId, to: res.msg.id });
    }
    bridge.handleMessage(data.toString());
  });

  ws.on('close', () => {
    bridge.stop();
    fb.close();
    openBridges.delete(bridge);
    logger.info('Lens connection closed', { instanceId });
  });
}

module.exports = { registerWatchRoutes, handleLensConnection, openBridges };
