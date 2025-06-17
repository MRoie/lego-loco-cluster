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
  console.log("Health check requested - live reloading test!");
  res.json({ status: "ok", timestamp: new Date().toISOString() });
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

// Enhanced instances endpoint that includes status and provisioning info
app.get("/api/instances", (req, res) => {
  try {
    console.log("Instances request");
    const instances = loadConfig("instances");
    const statusData = loadConfig("status");
    
    // Enhanced instance data with status information
    const enhancedInstances = instances.map(instance => ({
      ...instance,
      status: statusData[instance.id] || 'unknown',
      provisioned: statusData[instance.id] === 'ready' || statusData[instance.id] === 'running',
      ready: statusData[instance.id] === 'ready'
    }));
    
    res.json(enhancedInstances);
  } catch (e) {
    console.error("Instances config error:", e.message);
    res.status(503).json([]);
  }
});

// New endpoint to get provisioned instances only
app.get("/api/instances/provisioned", (req, res) => {
  try {
    console.log("Provisioned instances request");
    const instances = loadConfig("instances");
    const statusData = loadConfig("status");
    
    // Filter to only provisioned instances
    const provisionedInstances = instances
      .map(instance => ({
        ...instance,
        status: statusData[instance.id] || 'unknown',
        provisioned: statusData[instance.id] === 'ready' || statusData[instance.id] === 'running',
        ready: statusData[instance.id] === 'ready'
      }))
      .filter(instance => instance.provisioned);
    
    res.json(provisionedInstances);
  } catch (e) {
    console.error("Provisioned instances config error:", e.message);
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
      console.log(`VNC WS->TCP ${instanceId}: ${buffer.length} bytes`, buffer.slice(0, 32));
      tcpSocket.write(buffer);
    } catch (err) {
      console.error(`Error forwarding WebSocket to TCP for ${instanceId}:`, err.message);
    }
  });
  
  // Forward data from TCP socket to WebSocket
  tcpSocket.on('data', (data) => {
    try {
      console.log(`VNC TCP->WS ${instanceId}: ${data.length} bytes`, data.slice(0, 32));
      if (ws.readyState === ws.OPEN) {
        ws.send(data);
      }
    } catch (err) {
      console.error(`Error forwarding TCP to WebSocket for ${instanceId}:`, err.message);
    }
  });
  
  // Handle WebSocket close
  ws.on('close', (code, reason) => {
    console.log(`WebSocket closed for VNC bridge ${instanceId}, code: ${code}, reason: ${reason}`);
    tcpSocket.destroy();
  });
  
  // Handle WebSocket errors
  ws.on('error', (err) => {
    console.error(`WebSocket error for VNC bridge ${instanceId}:`, err.message);
    tcpSocket.destroy();
  });
}

// --- WebSocket Support for VNC ---
// VNC WebSocket server for handling VNC connections
const vncWss = new WebSocketServer({ noServer: true });
vncWss.on("error", (err) => {
  console.error("VNC WebSocket server error", err.message);
});

// Handle WebSocket upgrades for VNC connections
server.on("upgrade", (req, socket, head) => {
  console.log(`WebSocket upgrade request: ${req.url}`);
  
  // Match VNC proxy URLs
  const vncMatch = req.url.match(/^\/proxy\/vnc\/([^\/]+)/);
  if (vncMatch) {
    const instanceId = vncMatch[1];
    const target = getInstanceTarget(instanceId);
    
    if (target) {
      console.log(`VNC WebSocket proxy: ${instanceId} -> ${target}`);
      
      // Use the VNC WebSocket server
      vncWss.handleUpgrade(req, socket, head, (ws) => {
        createVNCBridge(ws, target, instanceId);
      });
    } else {
      console.error(`VNC WebSocket proxy: Unknown instance ${instanceId}`);
      socket.destroy();
    }
    return;
  }
  
  // Handle other WebSocket upgrades
  console.log("Unknown WebSocket upgrade, ignoring");
  socket.destroy();
});

console.log("WebSocket support added");

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
