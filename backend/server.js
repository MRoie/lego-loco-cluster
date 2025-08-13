const fs = require("fs");
const http = require("http");
const path = require("path");
const express = require("express");
const { WebSocketServer } = require("ws");
const httpProxy = require("http-proxy");
const net = require("net");
const url = require("url");
const logger = require("./utils/logger");
const client = require('prom-client');
const StreamQualityMonitor = require("./services/streamQualityMonitor");
const InstanceManager = require("./services/instanceManager");

const app = express();
const server = http.createServer(app);

// ========== PROMETHEUS METRICS CONFIGURATION ==========

// Create a Registry to register metrics
const register = new client.Registry();

// Register default metrics
client.collectDefaultMetrics({ register });

// Create custom metrics
const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.001, 0.005, 0.015, 0.05, 0.1, 0.2, 0.3, 0.4, 0.5, 1.0, 5.0, 10.0]
});

const activeConnections = new client.Gauge({
  name: 'active_connections_total',
  help: 'Number of active connections',
  labelNames: ['type']
});

// Register custom metrics
register.registerMetric(httpRequestDuration);
register.registerMetric(activeConnections);

// Middleware to track HTTP request duration
app.use((req, res, next) => {
  const start = Date.now();
  
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    const route = req.route ? req.route.path : req.path;
    httpRequestDuration.observe(
      { method: req.method, route, status_code: res.statusCode },
      duration
    );
  });
  
  next();
});

// Parse JSON bodies for API endpoints
app.use(express.json());

// Enhanced health endpoint with detailed system information
app.get("/health", (req, res) => {
  logger.info("Health check requested", { 
    userAgent: req.get('User-Agent'),
    remoteAddress: req.ip || req.connection.remoteAddress 
  });
  
  const healthData = {
    status: "ok",
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    version: process.env.npm_package_version || "unknown",
    node_version: process.version,
    memory: {
      used: Math.round(process.memoryUsage().heapUsed / 1024 / 1024),
      total: Math.round(process.memoryUsage().heapTotal / 1024 / 1024),
      external: Math.round(process.memoryUsage().external / 1024 / 1024),
      rss: Math.round(process.memoryUsage().rss / 1024 / 1024)
    },
    environment: process.env.NODE_ENV || "development",
    kubernetes_namespace: process.env.KUBERNETES_NAMESPACE || null,
    config_directory: FINAL_CONFIG_DIR,
    services: {
      instance_manager: instanceManager ? "initialized" : "not_initialized",
      quality_monitor: qualityMonitor ? "initialized" : "not_initialized"
    }
  };
  
  res.json(healthData);
});

// Readiness endpoint with dependency checks
app.get("/ready", async (req, res) => {
  logger.info("Readiness check requested", { 
    userAgent: req.get('User-Agent'),
    remoteAddress: req.ip || req.connection.remoteAddress 
  });
  
  const checks = {
    timestamp: new Date().toISOString(),
    overall_status: "unknown",
    checks: {}
  };
  
  let allHealthy = true;
  
  try {
    // Check instance manager initialization
    checks.checks.instance_manager = {
      status: instanceManager && instanceManager.initialized ? "healthy" : "unhealthy",
      message: instanceManager && instanceManager.initialized ? "Instance manager initialized" : "Instance manager not initialized"
    };
    if (!instanceManager || !instanceManager.initialized) {
      allHealthy = false;
    }
    
    // Check config directory accessibility
    try {
      const configExists = fs.existsSync(FINAL_CONFIG_DIR);
      checks.checks.config_directory = {
        status: configExists ? "healthy" : "unhealthy",
        message: configExists ? `Config directory accessible at ${FINAL_CONFIG_DIR}` : `Config directory not found at ${FINAL_CONFIG_DIR}`,
        path: FINAL_CONFIG_DIR
      };
      if (!configExists) {
        allHealthy = false;
      }
    } catch (error) {
      checks.checks.config_directory = {
        status: "unhealthy",
        message: `Config directory check failed: ${error.message}`,
        path: FINAL_CONFIG_DIR
      };
      allHealthy = false;
    }
    
    // Check essential config files
    const essentialConfigs = ["instances.json", "status.json"];
    checks.checks.config_files = {
      status: "healthy",
      message: "All essential config files accessible",
      files: {}
    };
    
    for (const configFile of essentialConfigs) {
      const configPath = path.join(FINAL_CONFIG_DIR, configFile);
      const exists = fs.existsSync(configPath);
      checks.checks.config_files.files[configFile] = {
        status: exists ? "accessible" : "missing",
        path: configPath
      };
      if (!exists) {
        checks.checks.config_files.status = "unhealthy";
        checks.checks.config_files.message = "Some essential config files are missing";
        allHealthy = false;
      }
    }
    
    // Check quality monitor
    checks.checks.quality_monitor = {
      status: qualityMonitor ? "healthy" : "unhealthy",
      message: qualityMonitor ? "Quality monitor initialized" : "Quality monitor not initialized"
    };
    if (!qualityMonitor) {
      allHealthy = false;
    }
    
    // Check if we can retrieve instances (tests the full dependency chain)
    try {
      const instances = await instanceManager.getInstances();
      checks.checks.instances_api = {
        status: "healthy",
        message: `Successfully retrieved ${instances.length} instances`,
        instance_count: instances.length
      };
    } catch (error) {
      checks.checks.instances_api = {
        status: "unhealthy",
        message: `Failed to retrieve instances: ${error.message}`
      };
      allHealthy = false;
    }
    
    // Memory check - warn if using more than 512MB
    const memoryUsage = process.memoryUsage().heapUsed / 1024 / 1024;
    checks.checks.memory = {
      status: memoryUsage < 512 ? "healthy" : "warning",
      message: `Memory usage: ${Math.round(memoryUsage)}MB`,
      usage_mb: Math.round(memoryUsage),
      threshold_mb: 512
    };
    
  } catch (error) {
    logger.error("Readiness check error:", error);
    allHealthy = false;
    checks.checks.general_error = {
      status: "unhealthy",
      message: `Readiness check failed: ${error.message}`
    };
  }
  
  checks.overall_status = allHealthy ? "ready" : "not_ready";
  
  // Return 503 Service Unavailable if not ready, 200 if ready
  const statusCode = allHealthy ? 200 : 503;
  
  if (!allHealthy) {
    logger.warn("Service not ready", { checks: checks.checks });
  }
  
  res.status(statusCode).json(checks);
});

// Prometheus metrics endpoint
app.get("/metrics", async (req, res) => {
  try {
    const metrics = await register.metrics();
    res.set('Content-Type', register.contentType);
    res.end(metrics);
  } catch (e) {
    logger.error("Failed to generate metrics:", e.message);
    res.status(500).end('Error generating metrics');
  }
});

// Directory that holds JSON config files
const CONFIG_DIR = process.env.CONFIG_DIR || path.join(__dirname, "../config");

// For Kubernetes deployment, check if the absolute path exists
const K8S_CONFIG_DIR = "/app/config";
const FINAL_CONFIG_DIR = fs.existsSync(K8S_CONFIG_DIR) ? K8S_CONFIG_DIR : CONFIG_DIR;

logger.info("Using config directory:", { configDirectory: FINAL_CONFIG_DIR });

// Initialize instance manager with auto-discovery
const instanceManager = new InstanceManager(FINAL_CONFIG_DIR);

// Initialize stream quality monitor with InstanceManager for Kubernetes-only discovery
const qualityMonitor = new StreamQualityMonitor(FINAL_CONFIG_DIR, instanceManager);

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

// Enhanced instances endpoint with auto-discovery support
app.get("/api/instances", async (req, res) => {
  try {
    console.log("Instances request");
    const instances = await instanceManager.getInstances();
    res.json(instances);
  } catch (e) {
    console.error("Instances config error:", e.message);
    res.status(503).json([]);
  }
});

// New endpoint to get provisioned instances only with auto-discovery
app.get("/api/instances/provisioned", async (req, res) => {
  try {
    console.log("Provisioned instances request");
    const provisionedInstances = await instanceManager.getProvisionedInstances();
    res.json(provisionedInstances);
  } catch (e) {
    console.error("Provisioned instances error:", e.message);
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
    console.error("Discovery info error:", e.message);
    res.status(500).json({ error: "Failed to get discovery info" });
  }
});

// New endpoint to refresh instance discovery
app.post("/api/instances/refresh", async (req, res) => {
  try {
    console.log("Manual instance discovery refresh requested");
    const instances = await instanceManager.refreshDiscovery();
    res.json({
      message: "Discovery refreshed successfully",
      instanceCount: instances.length,
      instances: instances
    });
  } catch (e) {
    console.error("Discovery refresh error:", e.message);
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
    console.error("Failed to get quality metrics:", e.message);
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
    console.error(`Failed to get quality metrics for ${req.params.instanceId}:`, e.message);
    res.status(500).json({ error: "Failed to get instance quality metrics" });
  }
});

// Get quality summary across all instances
app.get("/api/quality/summary", (req, res) => {
  try {
    const summary = qualityMonitor.getQualitySummary();
    res.json(summary);
  } catch (e) {
    console.error("Failed to get quality summary:", e.message);
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
    console.error("Failed to get deep health data:", e.message);
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
    console.error(`Failed to get deep health data for ${req.params.instanceId}:`, e.message);
    res.status(500).json({ error: "Failed to get instance deep health data" });
  }
});

// Trigger recovery for a specific instance
app.post("/api/quality/recover/:instanceId", (req, res) => {
  try {
    const instanceId = req.params.instanceId;
    const { forceRecovery = false } = req.body;
    
    console.log(`🚑 Manual recovery triggered for ${instanceId}`);
    
    // Get current metrics to determine failure type
    const metrics = qualityMonitor.getInstanceMetrics(instanceId);
    if (!metrics) {
      return res.status(404).json({ error: "Instance not found" });
    }
    
    const failureType = metrics.failureType || 'mixed';
    
    // Trigger recovery asynchronously
    qualityMonitor.executeRecoveryStrategy(instanceId, failureType)
      .then((success) => {
        console.log(`Recovery ${success ? 'succeeded' : 'failed'} for ${instanceId}`);
      })
      .catch((error) => {
        console.error(`Recovery error for ${instanceId}:`, error.message);
      });
    
    res.json({ 
      message: `Recovery initiated for ${instanceId}`, 
      failureType,
      forceRecovery 
    });
  } catch (e) {
    console.error(`Failed to trigger recovery for ${req.params.instanceId}:`, e.message);
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
    console.error("Failed to get recovery status:", e.message);
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
    console.error(`Failed to ${req.params.action} quality monitoring:`, e.message);
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
    console.error("Failed to read active state:", e.message);
    return [];
  }
}

function writeActive(ids) {
  try {
    const arr = Array.isArray(ids) ? ids.slice(0, 9) : [ids];
    fs.writeFileSync(ACTIVE_FILE, JSON.stringify({ active: arr }, null, 2));
  } catch (e) {
    console.error("Failed to write active state:", e.message);
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
    
    console.log(`Found instance ${id}: ${inst.vncUrl}`);
    // Use vncUrl for direct VNC connection instead of streamUrl (which is for noVNC web interface)
    return inst.vncUrl;
  } catch (e) {
    console.error("Failed to get instance target:", e.message);
    return null;
  }
}

// VNC WebSocket-to-TCP Bridge
function createVNCBridge(ws, targetUrl, instanceId) {
  console.log(`Creating VNC bridge for ${instanceId} to ${targetUrl}`);
  
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
      console.error("Active WS message error", e.message);
    }
  });
  ws.on("close", () => activeClients.delete(ws));
});

// Handle WebSocket upgrades for VNC connections
server.on("upgrade", (req, socket, head) => {
  console.log(`WebSocket upgrade request: ${req.url}`);
  
  // Match VNC proxy URLs
  const vncMatch = req.url.match(/^\/proxy\/vnc\/([^\/]+)/);
  if (vncMatch) {
    const instanceId = vncMatch[1];
    
    getInstanceTarget(instanceId).then(target => {
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
    }).catch(error => {
      console.error(`VNC WebSocket proxy error for ${instanceId}:`, error.message);
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
  console.log("Unknown WebSocket upgrade, ignoring");
  socket.destroy();
});

console.log("WebSocket support added");

// Start HTTP server first
server.listen(3001, () => {
  logger.info("Backend running on http://localhost:3001");
  logger.info("Config directory:", { configDirectory: FINAL_CONFIG_DIR });
  logger.info("Current active instances:", { activeInstances: readActive() });
  
  // Start quality monitoring
  logger.info("🔍 Starting stream quality monitoring service...");
  qualityMonitor.start();
  
  // Test config loading (only in non-test environments)
  if (process.env.NODE_ENV !== 'test' && !process.env.CI) {
    try {
      logger.info("Testing config loading...");
      const instances = loadConfig("instances");
      logger.info("Loaded instances:", { instanceCount: instances.length });
    } catch (e) {
      logger.error("Config loading test failed:", e.message);
    }
  } else {
    logger.info("⚠️  Test environment detected - skipping static config loading test");
  }
});

// Add uncaught exception handlers
process.on('uncaughtException', (err) => {
  logger.error('Uncaught Exception:', err);
  process.exit(1);
});

process.on('unhandledRejection', (reason, promise) => {
  logger.error('Unhandled Rejection at:', { promise, reason });
  process.exit(1);
});

logger.info("Server script loaded successfully");
