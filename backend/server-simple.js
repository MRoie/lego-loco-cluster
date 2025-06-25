const fs = require("fs");
const http = require("http");
const path = require("path");
const express = require("express");
const { WebSocketServer } = require("ws");
const httpProxy = require("http-proxy");
const net = require("net");
const url = require("url");

const app = express();
const server = http.createServer(app);

// simple health endpoint for Kubernetes-style checks
app.get("/health", (req, res) => {
  console.log("Health check requested");
  res.json({ status: "ok" });
});

// Directory that holds JSON config files
const CONFIG_DIR = process.env.CONFIG_DIR || path.join(__dirname, "../config");

// For Kubernetes deployment, check if the absolute path exists
const K8S_CONFIG_DIR = "/app/config";
const FINAL_CONFIG_DIR = fs.existsSync(K8S_CONFIG_DIR) ? K8S_CONFIG_DIR : CONFIG_DIR;

console.log("Using config directory:", FINAL_CONFIG_DIR);

// Serve frontend static build
app.use(express.static(path.join(__dirname, "../frontend/dist")));

// Helper to load JSON config files from the config directory
function loadConfig(name) {
  const file = path.join(FINAL_CONFIG_DIR, `${name}.json`);
  console.log(`Loading config from: ${file}`);
  
  if (!fs.existsSync(file)) {
    console.error(`Config file not found: ${file}`);
    throw new Error(`Config file not found: ${file}`);
  }
  
  let data = fs.readFileSync(file, "utf-8");
  console.log(`Raw config data for ${name}:`, data.substring(0, 200));
  
  // Allow simple // comments in JSON files
  data = data.replace(/^\s*\/\/.*$/gm, "");
  return JSON.parse(data);
}

// REST endpoint that returns any JSON config file
app.get("/api/config/:name", (req, res) => {
  try {
    console.log(`Config request for: ${req.params.name}`);
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
    console.log("Status request");
    const data = loadConfig("status");
    res.json(data);
  } catch (e) {
    console.error("Status config error:", e.message);
    res.status(503).json({});
  }
});

// Instances endpoint for dynamic frontend updates
app.get("/api/instances", (req, res) => {
  try {
    console.log("Instances request");
    const data = loadConfig("instances");
    res.json(data);
  } catch (e) {
    console.error("Instances config error:", e.message);
    res.status(503).json([]);
  }
});

// Generic proxy for VNC and WebRTC traffic
const proxy = httpProxy.createProxyServer({ ws: true, changeOrigin: true });

// Resolve an instance ID to its upstream target URL
function getInstanceTarget(id) {
  // Reload instances dynamically to support scaling
  try {
    const instances = loadConfig("instances");
    const inst = instances.find((i) => i.id === id);
    return inst ? inst.streamUrl : null;
  } catch (e) {
    console.error("Failed to load instances config:", e.message);
    return null;
  }
}

// VNC WebSocket-to-TCP Bridge
function createVNCBridge(ws, targetUrl, instanceId) {
  console.log(`Creating VNC bridge for ${instanceId} to ${targetUrl}`);
  
  // Parse the target URL to get host and port
  const parsed = url.parse(targetUrl);
  const host = parsed.hostname;
  const port = parseInt(parsed.port) || 5901;
  
  console.log(`Connecting to VNC server at ${host}:${port}`);
  
  // Create TCP connection to VNC server
  const tcpSocket = net.createConnection(port, host);
  
  tcpSocket.on('connect', () => {
    console.log(`VNC bridge connected to ${host}:${port}`);
  });
  
  tcpSocket.on('error', (err) => {
    console.error(`VNC TCP socket error for ${instanceId}:`, err.message);
    if (ws.readyState === ws.OPEN) {
      ws.close();
    }
  });
  
  tcpSocket.on('close', () => {
    console.log(`VNC TCP socket closed for ${instanceId}`);
    if (ws.readyState === ws.OPEN) {
      ws.close();
    }
  });
  
  // Forward data from WebSocket to TCP socket
  ws.on('message', (data) => {
    try {
      // Convert WebSocket message to Buffer if needed
      const buffer = Buffer.isBuffer(data) ? data : Buffer.from(data);
      tcpSocket.write(buffer);
    } catch (err) {
      console.error(`Error forwarding WebSocket to TCP for ${instanceId}:`, err.message);
    }
  });
  
  // Forward data from TCP socket to WebSocket
  tcpSocket.on('data', (data) => {
    try {
      if (ws.readyState === ws.OPEN) {
        ws.send(data);
      }
    } catch (err) {
      console.error(`Error forwarding TCP to WebSocket for ${instanceId}:`, err.message);
    }
  });
  
  // Handle WebSocket close
  ws.on('close', () => {
    console.log(`WebSocket closed for VNC bridge ${instanceId}`);
    tcpSocket.destroy();
  });
  
  // Handle WebSocket errors
  ws.on('error', (err) => {
    console.error(`WebSocket error for VNC bridge ${instanceId}:`, err.message);
    tcpSocket.destroy();
  });
}

// Start HTTP server first
server.listen(3001, () => {
  console.log("Backend running on http://localhost:3001");
  console.log("Config directory:", FINAL_CONFIG_DIR);
  
  // Test config loading
  try {
    console.log("Testing config loading...");
    const instances = loadConfig("instances");
    console.log("Loaded instances:", instances);
  } catch (e) {
    console.error("Config loading test failed:", e.message);
  }
});

// Add uncaught exception handlers
process.on('uncaughtException', (err) => {
  console.error('Uncaught Exception:', err);
  process.exit(1);
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('Unhandled Rejection at:', promise, 'reason:', reason);
  process.exit(1);
});

console.log("Server script loaded successfully");
