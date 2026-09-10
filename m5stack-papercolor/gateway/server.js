#!/usr/bin/env node
'use strict';

const path = require('path');
const http = require('http');
const express = require(path.resolve(__dirname, '../../backend/node_modules/express'));
const { WebSocketServer } = require(path.resolve(__dirname, '../../backend/node_modules/ws'));
const sharp = require(path.resolve(__dirname, '../../backend/node_modules/sharp'));
const RfbFramebuffer = require('../../backend/services/rfbFramebuffer');

const PORT = parseInt(process.env.PAPERCOLOR_PORT || '3002', 10);
const WIDTH = 600;
const HEIGHT = 400;
const JPEG_QUALITY = parseInt(process.env.PAPERCOLOR_JPEG_QUALITY || '82', 10);

function loadRegistry() {
  try {
    return JSON.parse(process.env.PAPERCOLOR_INSTANCES || '{}');
  } catch (e) {
    console.error('[papercolor] invalid PAPERCOLOR_INSTANCES JSON:', e.message);
    process.exit(2);
  }
}

const registry = loadRegistry();

function resolveInstance(id) {
  const found = registry[id];
  if (!found || !found.host) return null;
  return {
    host: found.host,
    port: Number(found.port || 5901),
    password: found.password,
  };
}

function viewportFor(frame) {
  const scale = Math.min(WIDTH / frame.width, HEIGHT / frame.height);
  const width = Math.max(1, Math.round(frame.width * scale));
  const height = Math.max(1, Math.round(frame.height * scale));
  return {
    x: Math.floor((WIDTH - width) / 2),
    y: Math.floor((HEIGHT - height) / 2),
    width,
    height,
  };
}

async function encodeFrame(frame) {
  const viewport = viewportFor(frame);
  const jpeg = await sharp(frame.pixels, {
    raw: { width: frame.width, height: frame.height, channels: frame.channels },
  })
    .resize(viewport.width, viewport.height, { fit: 'fill', kernel: sharp.kernel.lanczos3 })
    .extend({
      top: viewport.y,
      bottom: HEIGHT - viewport.y - viewport.height,
      left: viewport.x,
      right: WIDTH - viewport.x - viewport.width,
      background: { r: 255, g: 255, b: 255 },
    })
    .jpeg({ quality: JPEG_QUALITY, chromaSubsampling: '4:4:4' })
    .toBuffer();
  return { jpeg, viewport };
}

function panelToFramebuffer(frame, xNorm, yNorm) {
  const v = viewportFor(frame);
  const px = clamp01(xNorm) * (WIDTH - 1);
  const py = clamp01(yNorm) * (HEIGHT - 1);
  const fx = (px - v.x) / Math.max(1, v.width - 1);
  const fy = (py - v.y) / Math.max(1, v.height - 1);
  return { x: clamp01(fx), y: clamp01(fy) };
}

const app = express();
app.use(express.json());

app.get('/health', (_req, res) => {
  res.json({ ok: true, service: 'loco-papercolor', instances: Object.keys(registry) });
});

const server = http.createServer(app);
const wss = new WebSocketServer({ noServer: true });

async function attachClient(ws, initialId) {
  let currentId = initialId;
  let fb = null;
  let encoding = false;

  function sendJson(obj) {
    if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(obj));
  }

  function disconnectFb() {
    if (fb) {
      fb.close();
      fb = null;
    }
  }

  async function selectInstance(id) {
    const endpoint = resolveInstance(id);
    if (!endpoint) {
      sendJson({ type: 'error', error: `unknown instance: ${id}` });
      return false;
    }

    disconnectFb();
    currentId = id;
    fb = new RfbFramebuffer(endpoint);
    fb.connect();
    sendJson({ type: 'instance.active', id });
    return true;
  }

  async function sendFreshFrame() {
    if (encoding || !fb) return;
    const frame = fb.getFrame();
    if (!frame || !frame.pixels) {
      sendJson({ type: 'frame.pending', instanceId: currentId });
      return;
    }

    encoding = true;
    try {
      const { jpeg, viewport } = await encodeFrame(frame);
      if (ws.readyState === ws.OPEN) ws.send(jpeg, { binary: true });
      sendJson({
        type: 'frame.meta',
        instanceId: currentId,
        sourceAgeMs: frame.ageMs,
        encodedAt: Date.now(),
        sourceWidth: frame.width,
        sourceHeight: frame.height,
        viewport,
      });
    } catch (e) {
      sendJson({ type: 'error', error: `frame encode failed: ${e.message}` });
    } finally {
      encoding = false;
    }
  }

  function pointerFromPanel(x, y, buttons) {
    if (!fb) return;
    const frame = fb.getFrame();
    if (!frame) return;
    const p = panelToFramebuffer(frame, x, y);
    fb.sendPointer(p.x, p.y, Number(buttons || 0));
  }

  if (!(await selectInstance(initialId))) {
    ws.close(1008, 'unknown instance');
    return;
  }

  sendJson({
    type: 'hello',
    width: WIDTH,
    height: HEIGHT,
    instanceId: currentId,
    pullFrames: true,
  });

  ws.on('message', async (raw, isBinary) => {
    if (isBinary) return;

    let msg;
    try {
      msg = JSON.parse(raw.toString());
    } catch (_) {
      sendJson({ type: 'error', error: 'invalid JSON' });
      return;
    }

    switch (msg.type) {
      case 'frame.request':
        await sendFreshFrame();
        break;
      case 'pointer':
        pointerFromPanel(msg.x, msg.y, msg.buttons || 0);
        break;
      case 'click': {
        const x = clamp01(msg.x);
        const y = clamp01(msg.y);
        pointerFromPanel(x, y, 1);
        // LEGO Loco is more reliable with a deliberate hold than a tiny click.
        setTimeout(() => pointerFromPanel(x, y, 0), 180);
        break;
      }
      case 'instance.select':
        if (typeof msg.id === 'string') await selectInstance(msg.id);
        break;
      case 'ping':
        sendJson({ type: 'pong', ts: msg.ts || Date.now() });
        break;
      default:
        sendJson({ type: 'error', error: `unknown message type: ${msg.type}` });
    }
  });

  ws.on('close', disconnectFb);
  ws.on('error', disconnectFb);
}

function clamp01(v) {
  v = Number(v);
  if (!Number.isFinite(v)) return 0;
  return Math.min(1, Math.max(0, v));
}

server.on('upgrade', (req, socket, head) => {
  const match = req.url && req.url.match(/^\/ws\/papercolor\/([^/?]+)/);
  if (!match) {
    socket.destroy();
    return;
  }

  const instanceId = decodeURIComponent(match[1]);
  wss.handleUpgrade(req, socket, head, (ws) => {
    attachClient(ws, instanceId).catch((e) => {
      console.error('[papercolor] client failed:', e);
      try { ws.close(1011, 'gateway error'); } catch (_) {}
    });
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`[papercolor] gateway listening on :${PORT}`);
  console.log(`[papercolor] instances: ${Object.keys(registry).join(', ') || '(none)'}`);
});
