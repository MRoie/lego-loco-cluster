const fs = require("fs");
const http = require("http");
const path = require("path");
const express = require("express");
const { WebSocketServer } = require("ws");
const httpProxy = require("http-proxy");

const app = express();
const server = http.createServer(app);

// simple health endpoint for Kubernetes-style checks
app.get("/health", (req, res) => {
  res.json({ status: "ok" });
});

// Directory that holds JSON config files
const CONFIG_DIR = path.join(__dirname, "../config");

// Serve frontend static build
app.use(express.static(path.join(__dirname, "../frontend/dist")));

// Helper to load JSON config files from the config directory
function loadConfig(name) {
  const file = path.join(CONFIG_DIR, `${name}.json`);
  let data = fs.readFileSync(file, "utf-8");
  // Allow simple // comments in JSON files
  data = data.replace(/^\s*\/\/.*$/gm, "");
  return JSON.parse(data);
}

// REST endpoint that returns any JSON config file
app.get("/api/config/:name", (req, res) => {
  try {
    const data = loadConfig(req.params.name);
    res.json(data);
  } catch (e) {
    console.error(`Config ${req.params.name} not found`, e.message);
    res.status(404).json({ error: "config not found" });
  }
});

// Simple cluster status endpoint used by the UI for boot progress
app.get("/api/status", (req, res) => {
  try {
    const data = loadConfig("status");
    res.json(data);
  } catch (e) {
    res.status(503).json({});
  }
});

// --- VNC/WebRTC Proxy -------------------------------------------------------
// Map instance IDs to their streaming URLs
const instances = loadConfig("instances");
// Generic proxy for VNC and WebRTC traffic
const proxy = httpProxy.createProxyServer({ ws: true, changeOrigin: true });

// Resolve an instance ID to its upstream target URL
function getInstanceTarget(id) {
  const inst = instances.find((i) => i.id === id);
  return inst ? inst.streamUrl : null;
}

app.all("/proxy/vnc/:id/*", (req, res) => {
  const target = getInstanceTarget(req.params.id);
  if (!target) return res.status(404).send("Unknown instance");
  proxy.web(req, res, { target }, (err) => {
    console.error("Proxy error:", err.message);
    res.status(502).end();
  });
});

server.on("upgrade", (req, socket, head) => {
  const m = req.url.match(/^\/proxy\/vnc\/([^\/]+)/);
  if (m) {
    const target = getInstanceTarget(m[1]);
    if (target) {
      proxy.ws(req, socket, head, { target });
    }
  }
});

// --- WebSocket Signaling Server --------------------------------------------
// WebSocket signaling server used by the WebRTC hook
const wss = new WebSocketServer({ server, path: "/signal" });
wss.on("error", (err) => {
  console.error("WebSocket server error", err.message);
});
// Active peer connections keyed by ID
const peers = new Map();

// Handle incoming websocket connections for SDP exchange
wss.on("connection", (ws) => {
  let id = null;
  console.log("WebSocket client connected");

  ws.on("error", (err) => {
    console.error("WebSocket client error", err.message);
  });

  ws.on("message", (msg) => {
    let data;
    try {
      data = JSON.parse(msg);
    } catch (e) {
      return;
    }

    if (data.type === "register") {
      id = data.id || Math.random().toString(36).slice(2);
      peers.set(id, ws);
      ws.send(JSON.stringify({ type: "registered", id }));
      return;
    }

    if (data.type === "signal" && data.target && peers.has(data.target)) {
      peers.get(data.target).send(
        JSON.stringify({
          type: "signal",
          from: id,
          data: data.data,
        }),
      );
    }
  });

  ws.on("close", () => {
    if (id) peers.delete(id);
    console.log("WebSocket client disconnected", id);
  });
});

// Start HTTP and WebSocket services
server.listen(3001, () => {
  console.log("Backend running on http://localhost:3001");
});
