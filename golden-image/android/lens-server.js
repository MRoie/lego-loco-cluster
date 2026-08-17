#!/usr/bin/env node
// ============================================================================
// lens-server.js — minimal standalone Loco Lens bridge for the no-cluster case.
// ============================================================================
// On Android (Termux) / a single host there's no Kubernetes, no discovery, no
// React dashboard — just one QEMU with its VNC. This tiny server taps that VNC
// and serves the circular crop to the M5Stack watch. The full game view is
// whatever already shows the VNC (Termux:X11, a VNC viewer, or noVNC).
//
//   node lens-server.js
//
// Config (env):
//   LENS_INSTANCES   registry, default '{"local":{"host":"127.0.0.1","port":5901}}'
//   LENS_PORT        http/ws port (default 3001)
//   VNC_PASSWORD     optional VNC password applied to the default local instance
//
// Reuses the SAME lens modules as the cluster backend, so behaviour is
// identical — only discovery is replaced by the static registry.
// ============================================================================
const http = require('http');
const express = require('express');
const { WebSocketServer } = require('ws');

// Reuse the backend lens implementation (run from the repo, or copy backend/).
const BACKEND = process.env.LENS_BACKEND_DIR || require('path').resolve(__dirname, '../../backend');
const { registerWatchRoutes, handleLensConnection } = require(`${BACKEND}/routes/watch`);
const { InstanceResolver } = require(`${BACKEND}/services/instanceResolver`);

const PORT = parseInt(process.env.LENS_PORT || '3001', 10);
const DEFAULT_REGISTRY = JSON.stringify({
  local: { host: '127.0.0.1', port: 5901, password: process.env.VNC_PASSWORD || undefined },
});
const resolver = new InstanceResolver({
  mode: 'static',
  registry: process.env.LENS_INSTANCES || DEFAULT_REGISTRY,
});

const app = express();
app.use(express.json());
registerWatchRoutes(app, {});

// Minimal instance listing so a client can discover what's available.
app.get('/api/instances', (req, res) => {
  res.json({ mode: 'static', instances: resolver.listStaticInstances() });
});
app.get('/healthz', (req, res) => res.json({ ok: true, instances: resolver.listStaticInstances() }));

const server = http.createServer(app);
const lensWss = new WebSocketServer({ noServer: true });

server.on('upgrade', (req, socket, head) => {
  const m = req.url.match(/^\/ws\/lens\/([^/?]+)/);
  if (!m) { socket.destroy(); return; }
  lensWss.handleUpgrade(req, socket, head, (ws) => {
    handleLensConnection(ws, decodeURIComponent(m[1]), (id) => resolver.resolve(id));
  });
});

server.listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`Loco Lens (standalone) on :${PORT} — instances: ${resolver.listStaticInstances().join(', ')}`);
  console.log(`  watch → ws://<this-host>:${PORT}/ws/lens/local`);
});
