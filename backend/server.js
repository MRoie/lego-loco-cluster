const fs = require("fs");
const http = require("http");
const path = require("path");
const express = require("express");
const { WebSocketServer } = require("ws");
const httpProxy = require("http-proxy");
const net = require("net");
const url = require("url");
const logger = require("./utils/logger");
const StreamQualityMonitor = require("./services/streamQualityMonitor");
const InstanceManager = require("./services/instanceManager");

const app = express();
const server = http.createServer(app);

// Parse JSON bodies for API endpoints
app.use(express.json());

// simple health endpoint for Kubernetes-style checks
app.get("/health", (req, res) => {
  logger.info("Health check requested - live reloading test!");
  res.json({ status: "ok", timestamp: new Date().toISOString() });
});

// Directory that holds JSON config files
const CONFIG_DIR = process.env.CONFIG_DIR || path.join(__dirname, "../config");

// For Kubernetes deployment, check if the absolute path exists
const K8S_CONFIG_DIR = "/app/config";
const FINAL_CONFIG_DIR = fs.existsSync(K8S_CONFIG_DIR) ? K8S_CONFIG_DIR : CONFIG_DIR;

logger.info("Using config directory", { configDir: FINAL_CONFIG_DIR });

// Initialize instance manager with auto-discovery
const instanceManager = new InstanceManager(FINAL_CONFIG_DIR);

// Initialize stream quality monitor with InstanceManager for Kubernetes-only discovery
const qualityMonitor = new StreamQualityMonitor(FINAL_CONFIG_DIR, instanceManager);

// Serve frontend static build
app.use(express.static(path.join(__dirname, "../frontend/dist")));

// Helper to load JSON config files from the config directory
function loadConfig(name) {
  const file = path.join(FINAL_CONFIG_DIR, `${name}.json`);
  logger.info("Loading config from file", { file });
  
  if (!fs.existsSync(file)) {
    logger.error("Config file not found", { file });
    throw new Error(`Config file not found: ${file}`);
  }
  
  let data = fs.readFileSync(file, "utf-8");
  logger.debug("Raw config data loaded", { name, preview: data.substring(0, 200) });
  
  // Allow simple // comments in JSON files
  data = data.replace(/^\s*\/\/.*$/gm, "");
  return JSON.parse(data);
}

// REST endpoint that returns any JSON config file
app.get("/api/config/:name", (req, res) => {
  try {
    logger.info("Config request received", { configName: req.params.name });
    const data = loadConfig(req.params.name);
    res.json(data);
  } catch (e) {
    logger.error("Config not found", { configName: req.params.name, error: e.message });
    res.status(404).json({ error: "config not found" });
  }
});

// Simple cluster status endpoint used by the UI for boot progress
app.get("/api/status", (req, res) => {
  try {
    logger.info("Status request received");
    const data = loadConfig("status");
    res.json(data);
  } catch (e) {
    logger.error("Status config error", { error: e.message });
    res.status(503).json({});
  }
});

// Enhanced instances endpoint with auto-discovery support
app.get("/api/instances", async (req, res) => {
  try {
    logger.info("Instances request received");
    const instances = await instanceManager.getInstances();
    res.json(instances);
  } catch (e) {
    logger.error("Instances config error", { error: e.message });
    res.status(503).json([]);
  }
});

// New endpoint to get provisioned instances only with auto-discovery
app.get("/api/instances/provisioned", async (req, res) => {
  try {
    logger.info("Provisioned instances request received");
    const provisionedInstances = await instanceManager.getProvisionedInstances();
    res.json(provisionedInstances);
  } catch (e) {
    logger.error("Provisioned instances error", { error: e.message });
    res.status(503).json([]);
  }
});

// New endpoint for Kubernetes discovery information
app.get("/api/instances/discovery-info", async (req, res) => {
  try {
    const k8sInfo = await instanceManager.getKubernetesInfo();
    const isUsingK8sDiscovery = instanceManager.isUsingKubernetesDiscovery();
    
    res.json({
      kubernetesDiscovery: k8sInfo,
      usingAutoDiscovery: isUsingK8sDiscovery,
      fallbackToStatic: !isUsingK8sDiscovery
    });
  } catch (e) {
    logger.error("Discovery info error", { error: e.message });
    res.status(500).json({ error: "Failed to get discovery info" });
  }
});

// New endpoint to refresh instance discovery
app.post("/api/instances/refresh", async (req, res) => {
  try {
    logger.info("Manual instance discovery refresh requested");
    const instances = await instanceManager.refreshDiscovery();
    res.json({
      message: "Discovery refreshed successfully",
      instanceCount: instances.length,
      instances: instances
    });
  } catch (e) {
    logger.error("Discovery refresh error", { error: e.message });
    res.status(500).json({ error: "Failed to refresh discovery" });
  }
});

// ========== STREAM QUALITY MONITORING API ==========

// Get quality metrics for all instances
app.get("/api/quality/metrics", (req, res) => {
  try {
    const metrics = qualityMonitor.getAllMetrics();
    res.json(metrics);
  } catch (e) {
    logger.error("Failed to get quality metrics", { error: e.message });
    res.status(500).json({ error: "Failed to get quality metrics" });
  }
});

// Get quality metrics for a specific instance
app.get("/api/quality/metrics/:instanceId", (req, res) => {
  try {
    const { instanceId } = req.params;
    const metrics = qualityMonitor.getInstanceMetrics(instanceId);
    
    if (!metrics) {
      return res.status(404).json({ error: "Instance not found or not monitored" });
    }
    
    res.json(metrics);
  } catch (e) {
    logger.error("Failed to get quality metrics for instance", { instanceId: req.params.instanceId, error: e.message });
    res.status(500).json({ error: "Failed to get instance quality metrics" });
  }
});

// Get quality summary across all instances
app.get("/api/quality/summary", (req, res) => {
  try {
    const summary = qualityMonitor.getQualitySummary();
    res.json(summary);
  } catch (e) {
    logger.error("Failed to get quality summary", { error: e.message });
    res.status(500).json({ error: "Failed to get quality summary" });
  }
});

// Get deep health information for all instances
app.get("/api/quality/deep-health", (req, res) => {
  try {
    const metrics = qualityMonitor.getAllMetrics();
    const deepHealthData = {};
    
    for (const [instanceId, data] of Object.entries(metrics)) {
      if (data.deepHealth) {
        deepHealthData[instanceId] = {
          instanceId,
          timestamp: data.timestamp,
          overallStatus: data.deepHealth.overall_status || 'unknown',
          deepHealth: data.deepHealth,
          failureType: data.failureType || 'none',
          recoveryNeeded: data.recoveryNeeded || false,
          errors: data.errors || []
        };
      }
    }
    
    res.json(deepHealthData);
  } catch (e) {
    logger.error("Failed to get deep health data", { error: e.message });
    res.status(500).json({ error: "Failed to get deep health data" });
  }
});

// Get deep health information for a specific instance
app.get("/api/quality/deep-health/:instanceId", (req, res) => {
  try {
    const instanceId = req.params.instanceId;
    const metrics = qualityMonitor.getInstanceMetrics(instanceId);
    
    if (!metrics) {
      return res.status(404).json({ error: "Instance not found" });
    }
    
    const deepHealthData = {
      instanceId,
      timestamp: metrics.timestamp,
      overallStatus: metrics.deepHealth?.overall_status || 'unknown',
      deepHealth: metrics.deepHealth || null,
      failureType: metrics.failureType || 'none',
      recoveryNeeded: metrics.recoveryNeeded || false,
      errors: metrics.errors || []
    };
    
    res.json(deepHealthData);
  } catch (e) {
    logger.error("Failed to get deep health data for instance", { instanceId: req.params.instanceId, error: e.message });
    res.status(500).json({ error: "Failed to get instance deep health data" });
  }
});

// Trigger recovery for a specific instance
app.post("/api/quality/recover/:instanceId", (req, res) => {
  try {
    const instanceId = req.params.instanceId;
    const { forceRecovery = false } = req.body;
    
    logger.info("Manual recovery triggered", { instanceId, forceRecovery });
    
    // Get current metrics to determine failure type
    const metrics = qualityMonitor.getInstanceMetrics(instanceId);
    if (!metrics) {
      return res.status(404).json({ error: "Instance not found" });
    }
    
    const failureType = metrics.failureType || 'mixed';
    
    // Trigger recovery asynchronously
    qualityMonitor.executeRecoveryStrategy(instanceId, failureType)
      .then((success) => {
        logger.info("Recovery result", { instanceId, success });
      })
      .catch((error) => {
        logger.error("Recovery error", { instanceId, error: error.message });
      });
    
    res.json({ 
      message: `Recovery initiated for ${instanceId}`, 
      failureType,
      forceRecovery 
    });
  } catch (e) {
    logger.error("Failed to trigger recovery", { instanceId: req.params.instanceId, error: e.message });
    res.status(500).json({ error: "Failed to trigger recovery" });
  }
});

// Get recovery status and attempts
app.get("/api/quality/recovery-status", (req, res) => {
  try {
    const recoveryStatus = {};
    
    // Get recovery attempts for all instances
    for (const [instanceId, attempts] of qualityMonitor.recoveryAttempts || []) {
      recoveryStatus[instanceId] = {
        attempts,
        maxAttempts: qualityMonitor.maxRecoveryAttempts,
        canRecover: attempts < qualityMonitor.maxRecoveryAttempts
      };
    }
    
    res.json(recoveryStatus);
  } catch (e) {
    logger.error("Failed to get recovery status", { error: e.message });
    res.status(500).json({ error: "Failed to get recovery status" });
  }
});

// Start/stop quality monitoring
app.post("/api/quality/monitor/:action", (req, res) => {
  try {
    const { action } = req.params;
    
    if (action === 'start') {
      qualityMonitor.start();
      res.json({ status: 'started', message: 'Quality monitoring started' });
    } else if (action === 'stop') {
      qualityMonitor.stop();
      res.json({ status: 'stopped', message: 'Quality monitoring stopped' });
    } else {
      res.status(400).json({ error: 'Invalid action. Use start or stop' });
    }
  } catch (e) {
    logger.error("Failed to control quality monitoring", { action: req.params.action, error: e.message });
    res.status(500).json({ error: `Failed to ${req.params.action} quality monitoring` });
  }
});

// ---------------- Active Instance State ----------------
const ACTIVE_FILE = path.join(FINAL_CONFIG_DIR, "active.json");
function readActive() {
  try {
    const data = fs.readFileSync(ACTIVE_FILE, "utf-8");
    const val = JSON.parse(data).active;
    if (Array.isArray(val)) return val;
    if (val) return [val];
    return [];
  } catch (e) {
    logger.error("Failed to read active state", { error: e.message });
    return [];
  }
}

function writeActive(ids) {
  try {
    const arr = Array.isArray(ids) ? ids.slice(0, 9) : [ids];
    fs.writeFileSync(ACTIVE_FILE, JSON.stringify({ active: arr }, null, 2));
  } catch (e) {
    logger.error("Failed to write active state", { error: e.message });
  }
}

// Broadcast helpers
const activeClients = new Set();
function broadcastActive(ids) {
  for (const ws of activeClients) {
    if (ws.readyState === ws.OPEN) {
      ws.send(JSON.stringify({ active: ids }));
    }
  }
}

app.get("/api/active", (req, res) => {
  res.json({ active: readActive() });
});

app.post("/api/active", (req, res) => {
  const ids = req.body.ids || req.body.active || req.body.id;
  if (!ids) return res.status(400).json({ error: "id required" });
  writeActive(ids);
  broadcastActive(Array.isArray(ids) ? ids : [ids]);
  res.json({ active: Array.isArray(ids) ? ids : [ids] });
});

// Generic proxy for VNC and WebRTC traffic
const proxy = httpProxy.createProxyServer({ ws: true, changeOrigin: true });

// Resolve an instance ID to its upstream target URL
async function getInstanceTarget(id) {
  // Reload instances dynamically using instance manager
  try {
    const inst = await instanceManager.getInstanceById(id);
    if (!inst) {
      throw new Error(`Instance ${id} not found`);
    }
    
    logger.debug("Found instance target", { instanceId: id, vncUrl: inst.vncUrl });
    // Use vncUrl for direct VNC connection instead of streamUrl (which is for noVNC web interface)
    return inst.vncUrl;
  } catch (e) {
    logger.error("Failed to get instance target", { instanceId: id, error: e.message });
    return null;
  }
}

// VNC WebSocket-to-TCP Bridge
function createVNCBridge(ws, targetUrl, instanceId) {
  logger.info("Creating VNC bridge", { instanceId, targetUrl });
  
  // Parse the target URL to get host and port
  // targetUrl format is "localhost:5901" or "host:port"
  let host, port;
  if (targetUrl.includes('://')) {
    // Full URL format
    const parsed = url.parse(targetUrl);
    host = parsed.hostname;
    port = parseInt(parsed.port) || 5901;
  } else {
    // Simple host:port format
    const parts = targetUrl.split(':');
    host = parts[0] || 'localhost';
    port = parseInt(parts[1]) || 5901;
  }
  
  logger.info("Connecting to VNC server", { instanceId, host, port });
  
  // Create TCP connection to VNC server
  const tcpSocket = net.createConnection(port, host);
  
  tcpSocket.on('connect', () => {
    logger.info("VNC bridge connected", { instanceId, host, port });
  });
  
  tcpSocket.on('error', (err) => {
    logger.error("VNC TCP socket error", { instanceId, error: err.message });
    if (ws.readyState === ws.OPEN) {
      ws.close();
    }
  });
  
  tcpSocket.on('close', () => {
    logger.info("VNC TCP socket closed", { instanceId });
    if (ws.readyState === ws.OPEN) {
      ws.close();
    }
  });
  
  // Forward data from WebSocket to TCP socket
  ws.on('message', (data) => {
    try {
      // Convert WebSocket message to Buffer if needed
      const buffer = Buffer.isBuffer(data) ? data : Buffer.from(data);
      logger.debug("VNC data forwarding WS->TCP", { instanceId, bytes: buffer.length, preview: buffer.slice(0, 32) });
      tcpSocket.write(buffer);
    } catch (err) {
      logger.error("Error forwarding WebSocket to TCP", { instanceId, error: err.message });
    }
  });
  
  // Forward data from TCP socket to WebSocket
  tcpSocket.on('data', (data) => {
    try {
      logger.debug("VNC data forwarding TCP->WS", { instanceId, bytes: data.length, preview: data.slice(0, 32) });
      if (ws.readyState === ws.OPEN) {
        ws.send(data);
      }
    } catch (err) {
      logger.error("Error forwarding TCP to WebSocket", { instanceId, error: err.message });
    }
  });
  
  // Handle WebSocket close
  ws.on('close', (code, reason) => {
    logger.info("WebSocket closed for VNC bridge", { instanceId, code, reason });
    tcpSocket.destroy();
  });
  
  // Handle WebSocket errors
  ws.on('error', (err) => {
    logger.error("WebSocket error for VNC bridge", { instanceId, error: err.message });
    tcpSocket.destroy();
  });
}

// --- WebSocket Support for VNC ---
// VNC WebSocket server for handling VNC connections
const vncWss = new WebSocketServer({ noServer: true });
vncWss.on("error", (err) => {
  logger.error("VNC WebSocket server error", { error: err.message });
});

// WebSocket server for active focus updates
const activeWss = new WebSocketServer({ noServer: true });
activeWss.on("connection", (ws) => {
  activeClients.add(ws);
  ws.send(JSON.stringify({ active: readActive() }));
  ws.on("message", (msg) => {
    try {
      const data = JSON.parse(msg);
      const ids = data.ids || data.id || data.active;
      if (ids) {
        writeActive(ids);
        broadcastActive(Array.isArray(ids) ? ids : [ids]);
      }
    } catch (e) {
      logger.error("Active WebSocket message error", { error: e.message });
    }
  });
  ws.on("close", () => activeClients.delete(ws));
});

// Handle WebSocket upgrades for VNC connections
server.on("upgrade", (req, socket, head) => {
  logger.debug("WebSocket upgrade request", { url: req.url });
  
  // Match VNC proxy URLs
  const vncMatch = req.url.match(/^\/proxy\/vnc\/([^\/]+)/);
  if (vncMatch) {
    const instanceId = vncMatch[1];
    
    getInstanceTarget(instanceId).then(target => {
      if (target) {
        logger.info("VNC WebSocket proxy established", { instanceId, target });
        
        // Use the VNC WebSocket server
        vncWss.handleUpgrade(req, socket, head, (ws) => {
          createVNCBridge(ws, target, instanceId);
        });
      } else {
        logger.error("VNC WebSocket proxy: Unknown instance", { instanceId });
        socket.destroy();
      }
    }).catch(error => {
      logger.error("VNC WebSocket proxy error", { instanceId, error: error.message });
      socket.destroy();
    });
    
    return;
  }
  
  // Active focus WebSocket
  if (req.url === "/active") {
    activeWss.handleUpgrade(req, socket, head, (ws) => {
      activeWss.emit("connection", ws, req);
    });
    return;
  }

  // Handle other WebSocket upgrades
  logger.debug("Unknown WebSocket upgrade, ignoring");
  socket.destroy();
});

logger.info("WebSocket support added");

// Start HTTP server first
server.listen(3001, () => {
  logger.info("Backend running on http://localhost:3001");
  logger.info("Configuration details", { configDir: FINAL_CONFIG_DIR, activeInstances: readActive() });
  
  // Start quality monitoring
  logger.info("Starting stream quality monitoring service");
  qualityMonitor.start();
  
  // Test config loading (only in non-test environments)
  if (process.env.NODE_ENV !== 'test' && !process.env.CI) {
    try {
      logger.info("Testing config loading...");
      const instances = loadConfig("instances");
      logger.info("Loaded instances successfully", { instanceCount: instances.length });
    } catch (e) {
      logger.error("Config loading test failed", { error: e.message });
    }
  } else {
    logger.warn("Test environment detected - skipping static config loading test");
  }
});

// Add uncaught exception handlers
process.on('uncaughtException', (err) => {
  logger.error('Uncaught Exception', { error: err.message, stack: err.stack });
  process.exit(1);
});

process.on('unhandledRejection', (reason, promise) => {
  logger.error('Unhandled Rejection', { reason, promise });
  process.exit(1);
});

logger.info("Server script loaded successfully");
