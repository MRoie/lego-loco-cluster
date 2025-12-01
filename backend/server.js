/**
 * Lego Loco Cluster Backend Server
 * 
 * Enterprise-grade backend service providing:
 * - Enhanced health monitoring with Kubernetes probes (/health, /ready)
 * - Prometheus metrics collection (/metrics) 
 * - Instance management with auto-discovery (Kubernetes + static config)
 * - Stream quality monitoring and recovery
 * - VNC WebSocket proxy for remote access
 * - Active state synchronization across cluster
 * 
 * Health Endpoints:
 * - GET /health - Liveness probe with detailed system information
 * - GET /ready - Readiness probe with dependency validation
 * - GET /metrics - Prometheus metrics for monitoring/alerting
 * 
 * @version 1.0.0
 * @author Lego Loco Cluster Team
 */

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

// Global error handlers
process.on('uncaughtException', (err) => {
  console.error('UNCAUGHT EXCEPTION:', err);
  if (logger) logger.error('Uncaught Exception', { error: err.message, stack: err.stack });
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('UNHANDLED REJECTION:', reason);
  if (logger) logger.error('Unhandled Rejection', { reason });
});

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

    httpRequestDuration
      .labels(req.method, route, res.statusCode.toString())
      .observe(duration);
  });

  next();
});

// Track active HTTP connections
let activeHttpConnections = 0;
server.on('connection', (socket) => {
  activeHttpConnections++;
  activeConnections.labels('http').set(activeHttpConnections);

  let connectionClosed = false;
  const cleanupConnection = () => {
    if (!connectionClosed) {
      connectionClosed = true;
      activeHttpConnections--;
      activeConnections.labels('http').set(activeHttpConnections);
    }
  };

  socket.on('close', cleanupConnection);
  socket.on('error', cleanupConnection);
});

// ========== END PROMETHEUS METRICS CONFIGURATION ==========

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

// Parse JSON bodies for API endpoints
app.use(express.json());

/**
 * Enhanced health endpoint providing comprehensive system information
 * Used by Kubernetes liveness probes and general health monitoring
 * 
 * @returns {Object} Detailed health status including system metrics, service states, and configuration info
 */
app.get("/health", (req, res) => {
  logger.info("Health check requested", {
    userAgent: req.get('User-Agent'),
    remoteAddress: req.ip || req.connection.remoteAddress
  });

  const healthData = {
    status: "ok",
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    version: process.env.npm_package_version || "0.1.0",
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

/**
 * Comprehensive readiness endpoint for Kubernetes readiness probes
 * Validates all critical dependencies before declaring service ready
 * 
 * @returns {Object} Detailed readiness status with dependency checks
 * @status 200 - Service is ready and all dependencies are healthy
 * @status 503 - Service is not ready, one or more dependencies failed
 */
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

/**
 * Prometheus metrics endpoint for monitoring and alerting
 * Exposes HTTP request metrics, connection counts, and Node.js runtime metrics
 * 
 * @route GET /metrics
 * @returns {string} Prometheus format metrics
 */
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

// Serve frontend static build
app.use(express.static(path.join(__dirname, "../frontend/dist")));

/**
 * Helper function to load JSON config files from the config directory
 * Supports simple // comments in JSON files
 * 
 * @param {string} name - Config file name without .json extension
 * @returns {Object} Parsed JSON configuration
 */
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

/**
 * Enhanced instances endpoint with auto-discovery support
 * Supports both static configuration and Kubernetes-based discovery
 * 
 * @route GET /api/instances
 * @returns {Array} List of all available instances (static + auto-discovered)
 * @status 503 - Service unavailable if instance discovery fails
 */
app.get("/api/instances", async (req, res) => {
  try {
    logger.info("Instances request received", {
      userAgent: req.get('User-Agent'),
      remoteAddress: req.ip || req.connection.remoteAddress
    });
    const instances = await instanceManager.getInstances();
    logger.debug("Instances response prepared", { instanceCount: instances.length });
    res.json(instances);
  } catch (e) {
    logger.error("Instances config error", {
      error: e.message,
      stack: e.stack,
      requestUrl: req.url
    });
    res.status(503).json([]);
  }
});

/**
 * Get only provisioned (ready-to-use) instances
 * Filters instances to only include those marked as provisioned and available
 * 
 * @route GET /api/instances/provisioned
 * @returns {Array} List of provisioned instances only
 */
app.get("/api/instances/provisioned", async (req, res) => {
  try {
    logger.info("Provisioned instances request received", {
      userAgent: req.get('User-Agent'),
      remoteAddress: req.ip || req.connection.remoteAddress
    });
    const provisionedInstances = await instanceManager.getProvisionedInstances();
    logger.debug("Provisioned instances response prepared", { instanceCount: provisionedInstances.length });
    res.json(provisionedInstances);
  } catch (e) {
    logger.error("Provisioned instances error", {
      error: e.message,
      stack: e.stack,
      requestUrl: req.url
    });
    res.status(503).json([]);
  }
});

/**
 * Get Kubernetes discovery information and status
 * Provides insights into auto-discovery capabilities and fallback status
 * 
 * @route GET /api/instances/discovery-info
 * @returns {Object} Discovery status including Kubernetes availability and fallback info
 */
app.get("/api/instances/discovery-info", async (req, res) => {
  try {
    logger.debug("Discovery info request received", {
      userAgent: req.get('User-Agent'),
      remoteAddress: req.ip || req.connection.remoteAddress
    });
    const k8sInfo = await instanceManager.getKubernetesInfo();
    const isUsingK8sDiscovery = instanceManager.isUsingKubernetesDiscovery();

    const response = {
      kubernetesDiscovery: k8sInfo,
      usingAutoDiscovery: isUsingK8sDiscovery,
      fallbackToStatic: !isUsingK8sDiscovery
    };

    logger.debug("Discovery info response prepared", {
      usingAutoDiscovery: isUsingK8sDiscovery,
      kubernetesAvailable: !!k8sInfo
    });

    res.json(response);
  } catch (e) {
    logger.error("Discovery info error", {
      error: e.message,
      stack: e.stack,
      requestUrl: req.url
    });
    res.status(500).json({ error: "Failed to get discovery info" });
  }
});

// New endpoint to refresh instance discovery
app.post("/api/instances/refresh", async (req, res) => {
  try {
    logger.info("Manual instance discovery refresh requested", {
      userAgent: req.get('User-Agent'),
      remoteAddress: req.ip || req.connection.remoteAddress
    });
    const instances = await instanceManager.refreshDiscovery();
    logger.info("Discovery refresh completed successfully", { instanceCount: instances.length });
    res.json({
      message: "Discovery refreshed successfully",
      instanceCount: instances.length,
      instances: instances
    });
  } catch (e) {
    logger.error("Discovery refresh error", {
      error: e.message,
      stack: e.stack,
      requestUrl: req.url
    });
    res.status(500).json({ error: "Failed to refresh discovery" });
  }
});

// ========== STREAM QUALITY MONITORING API ==========

/**
 * Get quality metrics for all monitored instances
 * Returns video/audio quality, latency, and availability metrics
 * 
 * @route GET /api/quality/metrics
 * @returns {Object} Quality metrics for all instances
 */
app.get("/api/quality/metrics", (req, res) => {
  try {
    const metrics = qualityMonitor.getAllMetrics();
    res.json(metrics);
  } catch (e) {
    logger.error("Failed to get quality metrics", { error: e.message });
    res.status(500).json({ error: "Failed to get quality metrics" });
  }
});

/**
 * Get quality metrics for a specific instance
 * 
 * @route GET /api/quality/metrics/:instanceId
 * @param {string} instanceId - Instance identifier
 * @returns {Object} Quality metrics for the specified instance
 * @status 404 - Instance not found or not monitored
 */
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

/**
 * Get aggregated quality summary across all instances
 * Provides overall health status and alert conditions
 * 
 * @route GET /api/quality/summary
 * @returns {Object} Aggregated quality summary with overall health status
 */
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

/**
 * Resolve an instance ID to its upstream VNC target URL
 * Uses dynamic instance discovery to support both static and Kubernetes-discovered instances
 * 
 * @param {string} id - Instance identifier
 * @returns {string|null} VNC target URL (host:port format) or null if not found
 */
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

/**
 * Create a WebSocket-to-TCP bridge for VNC connections
 * Handles the protocol translation between WebSocket clients and VNC servers
 * Includes connection tracking, timeout handling, and proper cleanup
 * 
 * @param {WebSocket} ws - WebSocket connection from client
 * @param {string} targetUrl - VNC server target (host:port format)
 * @param {string} instanceId - Instance identifier for logging and metrics
 */
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

  // Connection state tracking
  let vncConnectionEstablished = false;
  let connectionClosed = false;

  // Connection cleanup function
  const cleanupConnection = (reason = 'unknown') => {
    if (!connectionClosed) {
      connectionClosed = true;
      console.log(`VNC connection cleanup for ${instanceId} (reason: ${reason})`);

      // Only decrement if connection was actually established
      if (vncConnectionEstablished) {
        activeVncConnections--;
        console.log(`VNC connections count decremented to ${activeVncConnections} for ${instanceId}`);
      }

      // Update metrics
      activeConnections.labels('websocket').set(activeVncConnections + activeWsConnections);

      // Clean up TCP socket
      if (tcpSocket && !tcpSocket.destroyed) {
        tcpSocket.destroy();
      }

      // Clean up WebSocket
      if (ws.readyState === ws.OPEN) {
        ws.close();
      }
    }
  };

  // Create TCP connection to VNC server
  const tcpSocket = net.createConnection(port, host);

  // TCP connection timeout (10 seconds)
  const connectionTimeout = setTimeout(() => {
    console.error(`VNC TCP connection timeout for ${instanceId} after 10 seconds`);
    cleanupConnection('tcp_timeout');
  }, 10000);

  tcpSocket.on('connect', () => {
    logger.info("VNC bridge connected successfully", { instanceId, host, port });
  });

  tcpSocket.on('error', (err) => {
    logger.error("VNC TCP socket error", {
      instanceId,
      error: err.message,
      code: err.code,
      host,
      port,
      stack: err.stack
    });
    if (ws.readyState === ws.OPEN) {
      ws.close(1000, 'TCP connection error');
    }
  });

  tcpSocket.on('close', () => {
    logger.info("VNC TCP socket closed", { instanceId, host, port });
    if (ws.readyState === ws.OPEN) {
      ws.close(1000, 'TCP connection closed');
    }
  });

  // Forward data from WebSocket to TCP socket
  ws.on('message', (data) => {
    if (connectionClosed || !vncConnectionEstablished || tcpSocket.destroyed) {
      console.warn(`Ignoring WebSocket message for ${instanceId} - connection not ready`);
      return;
    }

    try {
      // Convert WebSocket message to Buffer if needed
      const buffer = Buffer.isBuffer(data) ? data : Buffer.from(data);
      if (logger.level === 'debug') {
        logger.debug("VNC data forwarding WS->TCP", {
          instanceId,
          bytes: buffer.length,
          preview: buffer.slice(0, 32).toString('hex')
        });
      }
      tcpSocket.write(buffer);
    } catch (err) {
      logger.error("Error forwarding WebSocket to TCP", {
        instanceId,
        error: err.message,
        stack: err.stack
      });
    }
  });

  // Forward data from TCP socket to WebSocket
  tcpSocket.on('data', (data) => {
    if (connectionClosed || ws.readyState !== ws.OPEN) {
      console.warn(`Ignoring TCP data for ${instanceId} - WebSocket not ready`);
      return;
    }

    try {
      if (logger.level === 'debug') {
        logger.debug("VNC data forwarding TCP->WS", {
          instanceId,
          bytes: data.length,
          preview: data.slice(0, 32).toString('hex')
        });
      }
      if (ws.readyState === ws.OPEN) {
        ws.send(data);
      }
    } catch (err) {
      logger.error("Error forwarding TCP to WebSocket", {
        instanceId,
        error: err.message,
        stack: err.stack
      });
    }
  });

  // Handle WebSocket close
  ws.on('close', (code, reason) => {
    logger.info("WebSocket closed for VNC bridge", {
      instanceId,
      code,
      reason: reason?.toString()
    });
    tcpSocket.destroy();
  });

  // Handle WebSocket errors
  ws.on('error', (err) => {
    logger.error("WebSocket error for VNC bridge", {
      instanceId,
      error: err.message,
      code: err.code,
      stack: err.stack
    });
    tcpSocket.destroy();
  });

  // Set TCP socket timeout
  tcpSocket.setTimeout(30000); // 30 second idle timeout
}

// --- WebSocket Support for VNC ---
// VNC WebSocket server for handling VNC connections
const vncWss = new WebSocketServer({ noServer: true });
vncWss.on("error", (err) => {
  logger.error("VNC WebSocket server error", { error: err.message });
});

// WebSocket server for active focus updates
const activeWss = new WebSocketServer({ noServer: true });
let activeWsConnections = 0;
let activeVncConnections = 0;

activeWss.on("connection", (ws) => {
  activeClients.add(ws);
  activeWsConnections++;
  activeConnections.labels('websocket').set(activeVncConnections + activeWsConnections);

  let connectionClosed = false;
  const cleanupConnection = () => {
    if (!connectionClosed) {
      connectionClosed = true;
      activeClients.delete(ws);
      activeWsConnections--;
      activeConnections.labels('websocket').set(activeVncConnections + activeWsConnections);
    }
  };

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
  ws.on("close", cleanupConnection);
  ws.on("error", cleanupConnection);
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
