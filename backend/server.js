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
const udpToWebrtc = require('./services/udpToWebrtc');
const client = require('prom-client');
const StreamQualityMonitor = require("./services/streamQualityMonitor");
const InstanceManager = require("./services/instanceManager");
const rateLimit = require("./utils/rateLimit");
const validate = require("./utils/validate");
const helmet = require("helmet");

// Rate limiters
const writeRateLimit = rateLimit({ windowMs: 60_000, max: 30 });   // 30 req/min for general POST
const criticalRateLimit = rateLimit({ windowMs: 60_000, max: 5 });  // 5 req/min for recovery/restart
// Broad read-path limiter (concept from #82). Generous: the dashboard polls
// several endpoints every 5s per client. Override via API_RATE_LIMIT_MAX.
const apiReadRateLimit = rateLimit({
  windowMs: 60_000,
  max: parseInt(process.env.API_RATE_LIMIT_MAX || '600', 10),
});

const app = express();
const server = http.createServer(app);

// Security headers (concept from #82). CSP is disabled: this server only
// speaks JSON/WebSocket behind the nginx frontend, and a strict CSP here
// would apply to proxied content it does not own.
app.use(helmet({ contentSecurityPolicy: false }));

// Rate-limit the API surface, but never the kubelet probe or metrics paths —
// throttling liveness probes would turn load into restarts.
app.use((req, res, next) => {
  if (
    req.path === '/health' ||
    req.path === '/ready' ||
    req.path === '/metrics' ||
    !req.path.startsWith('/api/')
  ) {
    return next();
  }
  return apiReadRateLimit(req, res, next);
});

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

const vncBytesTransferred = new client.Counter({
  name: 'vnc_bytes_transferred_total',
  help: 'Total bytes transferred through VNC WebSocket proxy',
  labelNames: ['instance_id', 'direction']
});

const vncFramebufferUpdates = new client.Counter({
  name: 'vnc_framebuffer_updates_total',
  help: 'Total number of VNC framebuffer update messages detected',
  labelNames: ['instance_id']
});

const vncMessages = new client.Counter({
  name: 'vnc_messages_total',
  help: 'Total number of VNC protocol messages by type',
  labelNames: ['instance_id', 'message_type']
});

// Register custom metrics
register.registerMetric(httpRequestDuration);
register.registerMetric(activeConnections);
register.registerMetric(vncBytesTransferred);
register.registerMetric(vncFramebufferUpdates);
register.registerMetric(vncMessages);

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

// ========== FRONTEND OBSERVABILITY API ==========

/**
 * Ingest frontend logs
 * Allows the frontend to send structured logs to the backend
 * 
 * @route POST /api/logs/frontend
 */
app.post("/api/logs/frontend", writeRateLimit, validate({
  body: { level: { type: 'string' }, message: { type: 'string' } }
}), (req, res) => {
  try {
    const { level, message, ...context } = req.body;

    // Validate log level
    const validLevels = ['debug', 'info', 'warn', 'error'];
    const safeLevel = validLevels.includes(level) ? level : 'info';

    // Log with frontend service tag
    // The logger module exports specific methods (info, warn, etc.) but not a generic log method
    const logFn = logger[safeLevel];
    if (logFn) {
      logFn(message || 'No message provided', {
        service: 'frontend',
        ...context
      });
    } else {
      logger.info(message || 'No message provided', {
        service: 'frontend',
        originalLevel: level,
        ...context
      });
    }

    res.status(200).json({ status: 'ok' });
  } catch (e) {
    logger.error("Failed to process frontend log", { error: e.message });
    res.status(500).json({ error: "Failed to process log" });
  }
});

/**
 * Ingest frontend metrics
 * Allows the frontend to report Prometheus-style metrics
 * 
 * @route POST /api/metrics/frontend
 */
app.post("/api/metrics/frontend", writeRateLimit, (req, res) => {
  try {
    const metricsData = req.body;

    // In a real production system, we would aggregate these into Prometheus
    // For now, we log them so they are visible in backend logs
    logger.info("Frontend metrics received", {
      service: 'frontend-metrics',
      metrics: metricsData
    });

    // TODO: Integrate with prom-client to expose these metrics on /metrics

    res.status(200).json({ status: 'ok' });
  } catch (e) {
    logger.error("Failed to process frontend metrics", { error: e.message });
    res.status(500).json({ error: "Failed to process metrics" });
  }
});

// ========== END FRONTEND OBSERVABILITY API ==========

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
/**
 * Live per-instance status, derived from each emulator's own health endpoint.
 *
 * This used to serve a static config file, which meant it reported whatever
 * was written there forever — in practice "booting" for every instance while
 * two fully running guests served VNC. The VR scene renders this string on
 * the tiles, so the lie was on screen continuously.
 */
const statusCache = new Map();
const STATUS_TTL_MS = 5_000;

function fetchInstanceStatus(instance) {
  const cached = statusCache.get(instance.id);
  if (cached && Date.now() - cached.at < STATUS_TTL_MS) {
    return Promise.resolve(cached.value);
  }
  const host = instance.host || instance.podIP || instance.addresses?.podIP;
  if (!host) return Promise.resolve("unknown");
  return new Promise((resolve) => {
    const done = (value) => {
      statusCache.set(instance.id, { at: Date.now(), value });
      resolve(value);
    };
    const req = http.get(
      `http://${host}:${instance.healthPort || 8080}/health`,
      { timeout: 1500 },
      (response) => {
        let data = "";
        response.on("data", (chunk) => (data += chunk));
        response.on("end", () => {
          try {
            const h = JSON.parse(data);
            if (h.ready === true || h.overall_status === "healthy") return done("ready");
            if (h.pcem?.running || h.qemu_healthy) return done("booting");
            done("error");
          } catch {
            done("unknown");
          }
        });
      });
    req.on("error", () => done("unreachable"));
    req.on("timeout", () => { req.destroy(); done("unreachable"); });
  });
}

app.get("/api/status", async (req, res) => {
  try {
    const instances = await instanceManager.getInstances();
    const entries = await Promise.all(instances.map(async (i) => [i.id, await fetchInstanceStatus(i)]));
    res.json(Object.fromEntries(entries));
  } catch (e) {
    logger.error("Status error", { error: e.message });
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

/**
 * Each emulator publishes the address other guests reach it on — the one a
 * player types into LEGO LOCO's TCP/IP join box to join that instance's game.
 * It is a DHCP reservation keyed on the guest MAC, so it is stable across
 * restarts and knowable before the guest has finished booting.
 *
 * Cached, because /api/instances is polled continuously by every open tab and
 * this value changes about as often as the pod does. A failed probe caches a
 * null so one unreachable instance cannot stall the list on every poll.
 */
const GUEST_NETWORK_TTL_MS = 15_000;
const guestNetworkCache = new Map();

function fetchGuestNetwork(instance) {
  const cached = guestNetworkCache.get(instance.id);
  if (cached && Date.now() - cached.at < GUEST_NETWORK_TTL_MS) {
    return Promise.resolve(cached.value);
  }

  const host = instance.host || instance.podIP || instance.addresses?.podIP;
  if (!host) return Promise.resolve(null);

  return new Promise((resolve) => {
    const done = (value) => {
      guestNetworkCache.set(instance.id, { at: Date.now(), value });
      resolve(value);
    };
    const url = `http://${host}:${instance.healthPort || 8080}/health`;
    // Short timeout on purpose: this decorates the response, it must never be
    // the reason the instance list is slow.
    const req = http.get(url, { timeout: 1500 }, (response) => {
      let data = "";
      response.on("data", (chunk) => (data += chunk));
      response.on("end", () => {
        try {
          const health = JSON.parse(data);
          done(health.guest_network || null);
        } catch {
          done(null);
        }
      });
    });
    req.on("error", () => done(null));
    req.on("timeout", () => { req.destroy(); done(null); });
  });
}

app.get("/api/instances", async (req, res) => {
  try {
    logger.info("Instances request received", {
      userAgent: req.get('User-Agent'),
      remoteAddress: req.ip || req.connection.remoteAddress
    });
    const instances = await instanceManager.getInstances();
    const decorated = await Promise.all(instances.map(async (instance) => ({
      ...instance,
      guestNetwork: await fetchGuestNetwork(instance),
    })));
    logger.debug("Instances response prepared", { instanceCount: decorated.length });
    res.json(decorated);
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
 * Get live discovery status and instances
 * Primary endpoint for frontend polling in Phase 2
 * 
 * @route GET /api/instances/live
 * @returns {Object} Detailed discovery metadata and instances
 */
app.get("/api/instances/live", (req, res) => {
  try {
    const status = instanceManager.getDiscoveryStatus();
    res.json(status);
  } catch (e) {
    logger.error("Live instances error", {
      error: e.message,
      stack: e.stack
    });
    res.status(503).json({
      mode: 'error',
      error: e.message,
      instances: []
    });
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
app.post("/api/instances/refresh", criticalRateLimit, async (req, res) => {
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

// ==========================================
// Circuit Breaker Observability API
// ==========================================

/**
 * Get state and metrics for every circuit breaker protecting external calls.
 * @route GET /api/circuit-breakers
 */
app.get("/api/circuit-breakers", (req, res) => {
  const breakerManager = require("./services/circuitBreaker");
  res.json({
    summary: breakerManager.getSummary(),
    breakers: breakerManager.getAllMetrics(),
  });
});

/**
 * Get metrics for one circuit breaker by name.
 * @route GET /api/circuit-breakers/:name
 */
app.get("/api/circuit-breakers/:name", (req, res) => {
  const breakerManager = require("./services/circuitBreaker");
  const metrics = breakerManager.getMetrics(req.params.name);
  if (!metrics) {
    return res.status(404).json({ error: `Unknown circuit breaker: ${req.params.name}` });
  }
  res.json(metrics);
});

// ==========================================
// LAN Topology Dashboard API
// ==========================================

/**
 * Get LAN connectivity status across all emulator instances.
 * Probes each instance's health endpoint for cross-container L2 reachability,
 * ARP table, DirectPlay port checks (2300/47624), and network mode.
 *
 * @route GET /api/lan-status
 * @returns {Object} LAN topology with per-instance connectivity matrix
 */
app.get("/api/lan-status", async (req, res) => {
  try {
    const instances = await instanceManager.getInstances();
    const lanStatus = {
      timestamp: new Date().toISOString(),
      networkMode: process.env.NETWORK_MODE || "unknown",
      instanceCount: instances.length,
      instances: {},
      connectivity: [],
      overallHealthy: true,
    };

    // Probe each instance's health endpoint for LAN info
    const http = require("http");
    const probeInstance = (instance) => {
      return new Promise((resolve) => {
        const healthPort = instance.healthPort || 8080;
        const host = instance.host || instance.podIP || "localhost";
        const url = `http://${host}:${healthPort}/health`;

        const req = http.get(url, { timeout: 5000 }, (response) => {
          let data = "";
          response.on("data", (chunk) => (data += chunk));
          response.on("end", () => {
            try {
              const health = JSON.parse(data);
              resolve({
                id: instance.id,
                host,
                healthy: health.qemu_healthy || false,
                networkMode: health.network?.network_mode || "unknown",
                bridgeUp: health.network?.bridge_up || false,
                txPackets: health.network?.tx_packets || 0,
                rxPackets: health.network?.rx_packets || 0,
                txErrors: health.network?.tx_errors || 0,
                lanReachable: health.network?.lan_reachable || [],
                directplayPorts: {
                  tcp2300: health.network?.directplay_tcp_2300 || "unknown",
                  tcp47624: health.network?.directplay_tcp_47624 || "unknown",
                },
              });
            } catch (e) {
              resolve({ id: instance.id, host, healthy: false, error: "parse_error" });
            }
          });
        });
        req.on("error", () => {
          resolve({ id: instance.id, host, healthy: false, error: "unreachable" });
        });
        req.on("timeout", () => {
          req.destroy();
          resolve({ id: instance.id, host, healthy: false, error: "timeout" });
        });
      });
    };

    const results = await Promise.all(instances.map(probeInstance));

    for (const r of results) {
      lanStatus.instances[r.id] = r;
      if (!r.healthy) lanStatus.overallHealthy = false;
    }

    // Build connectivity matrix
    for (let i = 0; i < results.length; i++) {
      for (let j = i + 1; j < results.length; j++) {
        const a = results[i];
        const b = results[j];
        const reachable =
          (a.lanReachable && a.lanReachable.includes(b.host)) ||
          (b.lanReachable && b.lanReachable.includes(a.host));
        lanStatus.connectivity.push({
          from: a.id,
          to: b.id,
          reachable: reachable || false,
        });
      }
    }

    res.json(lanStatus);
  } catch (e) {
    logger.error("Failed to get LAN status", { error: e.message });
    res.status(500).json({ error: "Failed to get LAN status" });
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
app.post("/api/quality/recover/:instanceId", criticalRateLimit, validate({
  body: { forceRecovery: { type: 'boolean' } }
}), (req, res) => {
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

// Restart a single instance by deleting its pod. The StatefulSet recreates it
// with the same ordinal, the same PVC/disk and the same DNS name, so the
// frontend keeps the tile and simply watches it go not-ready -> ready again.
//
// This is deliberately not the /api/quality/recover path: that one drives
// StreamQualityMonitor, which is not started (see qualityMonitor.start() at
// the bottom of this file), so it 404s on every instance.
app.post("/api/instances/:instanceId/restart", criticalRateLimit, async (req, res) => {
  const instanceId = req.params.instanceId;
  try {
    const instance = await instanceManager.getInstanceById(instanceId);
    if (!instance) {
      return res.status(404).json({ error: `Instance ${instanceId} not found` });
    }

    const podName = instance.podName || instance.kubernetes?.targetRef?.name;
    const namespace = instance.kubernetes?.namespace ||
      instanceManager.kubernetesDiscovery?.getNamespace?.();

    if (!podName || !namespace) {
      return res.status(409).json({
        error: "Instance has no pod to restart",
        detail: "Restart requires Kubernetes discovery; static instances cannot be restarted."
      });
    }

    const k8sApi = instanceManager.kubernetesDiscovery?.k8sApi;
    if (!k8sApi) {
      return res.status(503).json({ error: "Kubernetes API unavailable" });
    }

    logger.info("Restarting instance", { instanceId, podName, namespace });
    await k8sApi.deleteNamespacedPod({ name: podName, namespace });

    // Drop the discovery cache so the tile reflects the new pod promptly
    // instead of showing the deleted one as ready for up to a cache TTL.
    instanceManager.cachedInstances = null;
    instanceManager.lastDiscoveryTime = null;

    res.json({
      message: `Restarting ${instanceId}`,
      instanceId,
      podName,
      namespace
    });
  } catch (e) {
    const status = e?.statusCode || e?.response?.statusCode;
    logger.error("Failed to restart instance", { instanceId, error: e.message, status });
    if (status === 403) {
      return res.status(403).json({
        error: "Not permitted to delete pods",
        detail: "The backend ServiceAccount needs delete on pods (see helm/loco-chart/templates/rbac.yaml)."
      });
    }
    res.status(500).json({ error: "Failed to restart instance", detail: e.message });
  }
});

// ---- Launch / scale: empty-slot provisioning ----
//
// The dashboard grid is a fixed 3x3, so nine replicas is a hard ceiling: a
// tenth pod would have no tile to land on.
const EMULATOR_MAX_REPLICAS = 9;

// The StatefulSet name is deliberately not hardcoded: prefer an explicit env
// override, then derive it the way discovery maps a pod to its parent (pod
// name minus the "-<ordinal>" suffix), and only then fall back to the
// headless-service name, which matches the StatefulSet name in the Helm chart.
function resolveEmulatorStatefulSetName() {
  if (process.env.EMULATOR_STATEFULSET_NAME) {
    return process.env.EMULATOR_STATEFULSET_NAME;
  }
  for (const inst of instanceManager.cachedInstances || []) {
    const podName = inst.podName || inst.kubernetes?.targetRef?.name;
    if (podName && /-\d+$/.test(podName)) {
      return podName.replace(/-\d+$/, '');
    }
  }
  return instanceManager.kubernetesDiscovery?.serviceName || 'loco-loco-emulator';
}

async function readEmulatorReplicas() {
  const discovery = instanceManager.kubernetesDiscovery;
  const namespace = discovery.getNamespace();
  const name = resolveEmulatorStatefulSetName();
  const response = await discovery.k8sAppsApi.readNamespacedStatefulSet({ name, namespace });
  // Handle both old (response.body) and new (response directly) client formats
  const body = response?.body || response;
  return { name, namespace, replicas: body?.spec?.replicas ?? 0 };
}

// Patch spec.replicas on the emulator StatefulSet and drop the discovery
// cache the way the restart endpoint does, so the grid reflects the change
// promptly instead of after a cache TTL.
async function scaleEmulatorStatefulSet(replicas) {
  const discovery = instanceManager.kubernetesDiscovery;
  const namespace = discovery.getNamespace();
  const name = resolveEmulatorStatefulSetName();

  // client-node v1 requires the patch content type via header middleware; a
  // merge patch is enough for a single scalar field.
  const k8s = discovery.k8s;
  const patchOptions = k8s?.setHeaderOptions && k8s?.PatchStrategy
    ? k8s.setHeaderOptions('Content-Type', k8s.PatchStrategy.MergePatch)
    : undefined;

  await discovery.k8sAppsApi.patchNamespacedStatefulSet(
    { name, namespace, body: { spec: { replicas } } },
    patchOptions
  );

  instanceManager.cachedInstances = null;
  instanceManager.lastDiscoveryTime = null;

  return { name, namespace, replicas };
}

function sendScaleError(res, e, action) {
  const status = e?.statusCode || e?.response?.statusCode;
  logger.error(`Failed to ${action}`, { error: e.message, status });
  if (status === 403) {
    return res.status(403).json({
      error: "Not permitted to patch statefulsets",
      detail: "The backend ServiceAccount needs patch on statefulsets (see helm/loco-chart/templates/rbac.yaml)."
    });
  }
  return res.status(500).json({ error: `Failed to ${action}`, detail: e.message });
}

// Boot a new instance by scaling the emulator StatefulSet up by one. Each pod
// self-provisions its identity (name, IP) from its ordinal, so "launch" is
// nothing more than replicas+1 — discovery then surfaces the new pod as a
// booting tile on the grid.
app.post("/api/instances/launch", criticalRateLimit, async (req, res) => {
  try {
    if (!instanceManager.kubernetesDiscovery?.k8sAppsApi) {
      return res.status(503).json({ error: "Kubernetes API unavailable" });
    }

    const { name, namespace, replicas } = await readEmulatorReplicas();
    if (replicas >= EMULATOR_MAX_REPLICAS) {
      return res.status(409).json({
        error: `All ${EMULATOR_MAX_REPLICAS} slots are in use — the 3x3 grid is full`,
        replicas
      });
    }

    const desired = replicas + 1;
    await scaleEmulatorStatefulSet(desired);
    logger.info("Launching new emulator instance", { statefulSet: name, namespace, replicas: desired });
    res.json({
      message: `Launching instance ${desired - 1} (${desired}/${EMULATOR_MAX_REPLICAS} slots)`,
      replicas: desired
    });
  } catch (e) {
    sendScaleError(res, e, "launch instance");
  }
});

// Explicit scale control for operators — same mechanics as launch, but the
// caller picks the replica count (1..9; 0 would kill the whole grid).
app.post("/api/instances/scale", criticalRateLimit, validate({
  body: { replicas: { type: 'number', required: true } }
}), async (req, res) => {
  try {
    if (!instanceManager.kubernetesDiscovery?.k8sAppsApi) {
      return res.status(503).json({ error: "Kubernetes API unavailable" });
    }

    const replicas = req.body.replicas;
    if (!Number.isInteger(replicas) || replicas < 1 || replicas > EMULATOR_MAX_REPLICAS) {
      return res.status(400).json({
        error: `replicas must be an integer between 1 and ${EMULATOR_MAX_REPLICAS}`
      });
    }

    const { name, namespace } = await scaleEmulatorStatefulSet(replicas);
    logger.info("Scaled emulator StatefulSet", { statefulSet: name, namespace, replicas });
    res.json({ message: `Scaled ${name} to ${replicas} replicas`, replicas });
  } catch (e) {
    sendScaleError(res, e, "scale instances");
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

/**
 * VNC configuration endpoint
 * Serves VNC implementation preferences from ConfigMap
 */
app.get('/api/config/vnc', (req, res) => {
  try {
    logger.info('VNC config requested', { userAgent: req.get('user-agent') });
    const vncConfig = loadConfig('vnc');
    res.json(vncConfig);
  } catch (e) {
    logger.error('Failed to load VNC config', { error: e.message });
    // Return default config if file not found
    res.json({
      implementation: 'novnc',
      fallbackEnabled: true,
      maxRetries: 3
    });
  }
});

// Start/stop quality monitoring
app.post("/api/quality/monitor/:action", criticalRateLimit, (req, res) => {
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

// ========== LIVE BENCHMARK API ==========
/**
 * Real-time benchmark metrics endpoint.
 * Probes all emulator health endpoints and returns aggregated metrics
/**
 * GET /api/lan-status — LAN connectivity status across all emulator instances.
 * Reports socket networking state, cross-instance reachability, and DirectPlay port status.
 */
app.get("/api/lan-status", async (req, res) => {
  try {
    const instances = await instanceManager.getInstances();
    const httpLib = require("http");

    const checkLan = (instance) => {
      return new Promise((resolve) => {
        const healthPort = (instance.ports && instance.ports.health) || instance.healthPort || 8080;
        const host = (instance.addresses && (instance.addresses.podIP || instance.addresses.dnsName)) || instance.host || instance.podIP || "localhost";
        const url = `http://${host}:${healthPort}/health`;

        const request = httpLib.get(url, { timeout: 5000 }, (response) => {
          let data = "";
          response.on("data", (chunk) => (data += chunk));
          response.on("end", () => {
            try {
              const h = JSON.parse(data);
              resolve({
                id: instance.id,
                host,
                networkOk: (h.network?.bridge_up && h.network?.tap_up) || false,
                bridgeUp: h.network?.bridge_up || false,
                tapUp: h.network?.tap_up || false,
                txBytes: h.network?.tx_bytes || 0,
                rxBytes: h.network?.rx_bytes || 0,
                socketMode: process.env.NETWORK_MODE || "socket",
                reachable: true,
              });
            } catch (e) {
              resolve({ id: instance.id, host, reachable: true, networkOk: false, error: "parse_error" });
            }
          });
        });
        request.on("error", () => resolve({ id: instance.id, host, reachable: false, networkOk: false, error: "unreachable" }));
        request.on("timeout", () => { request.destroy(); resolve({ id: instance.id, host, reachable: false, networkOk: false, error: "timeout" }); });
      });
    };

    const results = await Promise.all(instances.map(checkLan));
    const allReachable = results.every(r => r.reachable);
    const allNetworkOk = results.every(r => r.networkOk);

    res.json({
      timestamp: new Date().toISOString(),
      networkMode: process.env.NETWORK_MODE || "socket",
      instances: results,
      summary: {
        totalCount: results.length,
        reachableCount: results.filter(r => r.reachable).length,
        networkOkCount: results.filter(r => r.networkOk).length,
        allReachable,
        allNetworkOk,
        socketMasterHost: process.env.SOCKET_MASTER_HOST || "auto",
      },
    });
  } catch (e) {
    logger.error("LAN status check failed", { error: e.message });
    res.status(500).json({ error: "LAN status check failed" });
  }
});

/**
 * GET /api/benchmark/live — Real-time benchmark metrics for all emulator instances.
 * suitable for the live overlay dashboard.
 *
 * @route GET /api/benchmark/live
 * @returns {Object} { instances: [...], summary: {...} }
 */
app.get("/api/benchmark/live", async (req, res) => {
  try {
    const instances = await instanceManager.getInstances();
    const httpLib = require("http");

    const probeInstance = (instance) => {
      return new Promise((resolve) => {
        const healthPort = (instance.ports && instance.ports.health) || instance.healthPort || 8080;
        const host = (instance.addresses && (instance.addresses.podIP || instance.addresses.dnsName)) || instance.host || instance.podIP || "localhost";
        const url = `http://${host}:${healthPort}/health`;
        const t0 = Date.now();

        const request = httpLib.get(url, { timeout: 5000 }, (response) => {
          let data = "";
          response.on("data", (chunk) => (data += chunk));
          response.on("end", () => {
            const latency = Date.now() - t0;
            try {
              const h = JSON.parse(data);
              // Two emulator flavors publish health here and they do not agree
              // on field names. Reading only QEMU's shape made every PCem
              // instance show up as ERR with three red crosses while it was
              // running perfectly — the columns were reporting the absence of
              // a field, not the state of the machine. Accept either.
              resolve({
                id: instance.id,
                instanceId: instance.instanceId || instance.id,
                host,
                emulator: h.emulator || "qemu",
                healthy: h.overall_status === "healthy" || h.ready === true,
                fps: h.video?.estimated_frame_rate || 0,
                // PCem has no frame-rate meter; what matters for it is whether
                // it is holding real-time speed against the emulated Pentium.
                speedPercent: h.video?.emulated_speed_percent ?? null,
                latency,
                cpu: h.performance?.cpu_usage || 0,
                memory: h.performance?.memory_usage || 0,
                qemuHealthy: h.qemu_healthy || h.pcem?.running || false,
                displayActive: h.video?.display_active || h.video?.vnc_available || false,
                networkOk: (h.network?.bridge_up && h.network?.tap_up) ||
                  h.guest_network?.carrier === 1 || false,
                // The address other guests reach this one on — what a player
                // types into LEGO LOCO's TCP/IP join box.
                guestIp: h.guest_network?.ip || null,
                guestLink: h.guest_network?.carrier === 1,
                vncAvailable: h.video?.vnc_available || false,
                audioRunning: h.audio?.pulse_running || false,
              });
            } catch (e) {
              resolve({ id: instance.id, instanceId: instance.id, host, healthy: false, error: "parse_error", latency });
            }
          });
        });
        request.on("error", () => resolve({ id: instance.id, instanceId: instance.id, host, healthy: false, error: "unreachable", latency: Date.now() - t0 }));
        request.on("timeout", () => { request.destroy(); resolve({ id: instance.id, instanceId: instance.id, host, healthy: false, error: "timeout", latency: 5000 }); });
      });
    };

    const results = await Promise.all(instances.map(probeInstance));

    const healthy = results.filter(r => r.healthy);
    const fpsVals = results.filter(r => r.fps > 0).map(r => r.fps);
    const latVals = results.filter(r => r.latency > 0).map(r => r.latency);
    const cpuVals = results.filter(r => r.cpu > 0).map(r => r.cpu);
    const memVals = results.filter(r => r.memory > 0).map(r => r.memory);
    const avg = arr => arr.length ? arr.reduce((a, b) => a + b, 0) / arr.length : 0;

    res.json({
      timestamp: new Date().toISOString(),
      instances: results,
      summary: {
        totalCount: results.length,
        healthyCount: healthy.length,
        allHealthy: healthy.length === results.length && results.length > 0,
        avgFps: Math.round(avg(fpsVals)),
        avgLatency: Math.round(avg(latVals)),
        avgCpu: Math.round(avg(cpuVals) * 10) / 10,
        avgMemory: Math.round(avg(memVals) * 10) / 10,
        networkMode: process.env.NETWORK_MODE || "socket",
      },
    });
  } catch (e) {
    logger.error("Benchmark live probe failed", { error: e.message });
    res.status(500).json({ error: "Benchmark probe failed" });
  }
});

app.get("/api/active", (req, res) => {
  res.json({ active: readActive() });
});

app.post("/api/active", writeRateLimit, validate({
  body: { ids: { type: 'array' }, id: { type: 'string' } }
}), (req, res) => {
  const ids = req.body.ids || req.body.active || req.body.id;
  if (!ids) return res.status(400).json({ error: "id required" });
  writeActive(ids);
  broadcastActive(Array.isArray(ids) ? ids : [ids]);
  res.json({ active: Array.isArray(ids) ? ids : [ids] });
});

// Quality metrics endpoints
app.get('/api/quality/metrics/:instanceId', (req, res) => {
  const { instanceId } = req.params;
  logger.info('Quality metrics requested', { instanceId, userAgent: req.get('user-agent') });

  const metrics = {
    instanceId,
    timestamp: new Date().toISOString(),
    vnc: {
      connected: activeVncConnections > 0,
      bytesTransferred: 0,
      framebufferUpdates: 0,
      latencyMs: null
    },
    webrtc: {
      connected: false,
      iceConnectionState: 'new'
    }
  };

  res.json(metrics);
});

app.get('/api/quality/deep-health/:instanceId', (req, res) => {
  const { instanceId } = req.params;
  logger.info('Deep health check requested', { instanceId, userAgent: req.get('user-agent') });

  res.json({
    instanceId,
    timestamp: new Date().toISOString(),
    status: 'healthy',
    checks: {
      vnc: { status: 'ok' },
      emulator: { status: 'ok' },
      network: { status: 'ok' }
    }
  });
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
/**
 * Create a WebSocket-to-TCP bridge for VNC connections
 * Handles the protocol translation between WebSocket clients and VNC servers
 * Includes connection tracking, timeout handling, and proper cleanup
 * 
 * @param {WebSocket} ws - WebSocket connection from client
 * @param {string} targetUrl - VNC server target (host:port format)
 * @param {string} instanceId - Instance identifier for logging and metrics
 * @param {string} traceId - Distributed trace identifier
 */
function createVNCBridge(ws, targetUrl, instanceId, traceId = 'unknown') {
  const logCtx = { instanceId, traceId };
  logger.info("Creating VNC bridge", { ...logCtx, targetUrl });

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

  logger.info("Connecting to VNC server", { ...logCtx, host, port });

  // Connection state tracking
  let vncConnectionEstablished = false;
  let connectionClosed = false;
  let firstPacketReceived = false;

  // Connection cleanup function
  const cleanupConnection = (reason = 'unknown') => {
    if (!connectionClosed) {
      connectionClosed = true;
      logger.info(`VNC connection cleanup`, { ...logCtx, reason });

      // Only decrement if connection was actually established
      if (vncConnectionEstablished) {
        activeVncConnections--;
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
  // Pointer events are tiny writes on an interactive path; Nagle would hold
  // them for the previous segment's ACK. In-cluster the RTT makes that ~free,
  // but a headset on the LAN talks through this exact socket — and Node 18's
  // net.createConnection defaults noDelay to false.
  tcpSocket.setNoDelay(true);

  // TCP connection timeout (10 seconds)
  const connectionTimeout = setTimeout(() => {
    logger.error(`VNC TCP connection timeout`, { ...logCtx, timeoutMs: 10000 });
    cleanupConnection('tcp_timeout');
  }, 10000);

  tcpSocket.on('connect', () => {
    clearTimeout(connectionTimeout);
    vncConnectionEstablished = true;
    activeVncConnections++;
    logger.info("VNC TCP connected", { ...logCtx, host, port });
  });

  tcpSocket.on('error', (err) => {
    logger.error("VNC TCP socket error", {
      ...logCtx,
      error: err.message,
      code: err.code,
      host,
      port
    });
    if (ws.readyState === ws.OPEN) {
      ws.close(1000, 'TCP connection error');
    }
  });

  tcpSocket.on('close', () => {
    logger.info("VNC TCP socket closed", logCtx);
    if (ws.readyState === ws.OPEN) {
      ws.close(1000, 'TCP connection closed');
    }
  });

  // Forward data from WebSocket to TCP socket
  ws.on('message', (data) => {
    if (connectionClosed || !vncConnectionEstablished || tcpSocket.destroyed) {
      return;
    }

    try {
      // Convert WebSocket message to Buffer if needed
      const buffer = Buffer.isBuffer(data) ? data : Buffer.from(data);

      // Track bytes sent from client to VNC server
      vncBytesTransferred.labels(instanceId, 'client_to_server').inc(buffer.length);

      // logger.debug("WS->TCP", { ...logCtx, bytes: buffer.length });
      tcpSocket.write(buffer);
    } catch (err) {
      logger.error("Error forwarding WebSocket to TCP", {
        ...logCtx,
        error: err.message
      });
    }
  });

  // Forward data from TCP socket to WebSocket
  // + RFB Sniffer with framebuffer detection
  tcpSocket.on('data', (data) => {
    if (connectionClosed || ws.readyState !== ws.OPEN) {
      return;
    }

    try {
      if (!firstPacketReceived) {
        firstPacketReceived = true;
        const potentialProtocol = data.slice(0, 12).toString('utf-8');
        logger.info("VNC First Packet Sniff (RFB Handshake)", {
          ...logCtx,
          length: data.length,
          hexHead: data.slice(0, 12).toString('hex'),
          asciiHead: potentialProtocol,
          isValidRFB: potentialProtocol.startsWith('RFB ')
        });
      }

      // Track bytes sent from VNC server to client
      vncBytesTransferred.labels(instanceId, 'server_to_client').inc(data.length);

      // Detect VNC message types (after handshake)
      if (firstPacketReceived && data.length > 0) {
        const messageType = data[0];

        // VNC Server to Client message types
        switch (messageType) {
          case 0: // FramebufferUpdate
            vncFramebufferUpdates.labels(instanceId).inc();
            vncMessages.labels(instanceId, 'framebuffer_update').inc();
            logger.debug("VNC FramebufferUpdate detected", { ...logCtx, bytes: data.length });
            break;
          case 1: // SetColorMapEntries
            vncMessages.labels(instanceId, 'set_colormap').inc();
            break;
          case 2: // Bell
            vncMessages.labels(instanceId, 'bell').inc();
            break;
          case 3: // ServerCutText
            vncMessages.labels(instanceId, 'server_cut_text').inc();
            break;
          default:
            // Unknown or client-to-server message in stream
            break;
        }
      }

      if (ws.readyState === ws.OPEN) {
        ws.send(data);
      }
    } catch (err) {
      logger.error("Error forwarding TCP to WebSocket", {
        ...logCtx,
        error: err.message
      });
    }
  });

  // Handle WebSocket close
  ws.on('close', (code, reason) => {
    logger.info("WebSocket closed", {
      ...logCtx,
      code,
      reason: reason?.toString()
    });
    tcpSocket.destroy();
  });

  // Handle WebSocket errors
  ws.on('error', (err) => {
    logger.error("WebSocket error", {
      ...logCtx,
      error: err.message,
      code: err.code
    });
    tcpSocket.destroy();
  });

  // Set TCP socket timeout
  tcpSocket.setTimeout(30000); // 30 second idle timeout
}

// Port every emulator pod exposes raw guest PCM on (PulseAudio's
// module-simple-protocol-tcp, started by the PCem entrypoint). One knob, not
// per-instance: all instances run the same container.
const EMULATOR_AUDIO_PORT = parseInt(process.env.EMULATOR_AUDIO_PORT || '5902', 10);
const EMULATOR_AUDIO_RATE = parseInt(process.env.EMULATOR_AUDIO_RATE || '48000', 10);

/**
 * Create a one-way TCP->WebSocket bridge for guest audio.
 *
 * Mirrors createVNCBridge but strictly server-to-client: the upstream is a
 * headerless s16le PCM stream (48 kHz stereo) from the pod's PulseAudio tap,
 * and the browser has nothing to say back. The first frame sent is a single
 * JSON text message describing the format so the client never has to guess;
 * everything after it is binary PCM.
 *
 * @param {WebSocket} ws - WebSocket connection from client
 * @param {string} targetUrl - VNC target ("host:port") — only the host is used;
 *                             audio always lives on EMULATOR_AUDIO_PORT
 * @param {string} instanceId - Instance identifier for logging
 * @param {string} traceId - Distributed trace identifier
 */
function createAudioBridge(ws, targetUrl, instanceId, traceId = 'unknown') {
  const logCtx = { instanceId, traceId };

  // Reuse the instance's VNC target for the host; the PCM port is fixed.
  let host;
  if (targetUrl.includes('://')) {
    host = url.parse(targetUrl).hostname;
  } else {
    host = targetUrl.split(':')[0] || 'localhost';
  }
  const port = EMULATOR_AUDIO_PORT;

  logger.info("Creating audio bridge", { ...logCtx, host, port });

  let connectionClosed = false;
  const cleanupConnection = (reason = 'unknown') => {
    if (connectionClosed) return;
    connectionClosed = true;
    logger.info("Audio connection cleanup", { ...logCtx, reason });
    if (tcpSocket && !tcpSocket.destroyed) {
      tcpSocket.destroy();
    }
    if (ws.readyState === ws.OPEN) {
      ws.close();
    }
  };

  const tcpSocket = net.createConnection(port, host);
  // Audio chunks are small and continuous; Nagle would batch them into
  // bursty, later-arriving segments for no bandwidth win worth having.
  tcpSocket.setNoDelay(true);

  const connectionTimeout = setTimeout(() => {
    logger.error("Audio TCP connection timeout", { ...logCtx, timeoutMs: 10000 });
    cleanupConnection('tcp_timeout');
  }, 10000);

  tcpSocket.on('connect', () => {
    clearTimeout(connectionTimeout);
    logger.info("Audio TCP connected", { ...logCtx, host, port });
    // One text frame up front so the client can configure its player before
    // the first PCM bytes land. The stream itself is headerless.
    if (ws.readyState === ws.OPEN) {
      ws.send(JSON.stringify({
        type: 'format',
        rate: EMULATOR_AUDIO_RATE,
        channels: 2,
        format: 's16le',
      }));
    }
  });

  tcpSocket.on('data', (data) => {
    if (connectionClosed || ws.readyState !== ws.OPEN) return;
    // Latency-shedding: if the client isn't draining (slow network, tab in
    // the background), DROP the chunk rather than queue it. Buffered PCM is
    // pure added latency — it can never be played "later", only late — so
    // the queue must never be allowed to accumulate.
    if (ws.bufferedAmount > 65536) return;
    ws.send(data);
  });

  tcpSocket.on('error', (err) => {
    logger.error("Audio TCP socket error", { ...logCtx, error: err.message, code: err.code, host, port });
    cleanupConnection('tcp_error');
  });

  tcpSocket.on('close', () => cleanupConnection('tcp_closed'));

  // One-way bridge: the client has no business writing PCM back. Swallow
  // anything that does arrive (application-level pings included) rather than
  // feeding it to the PulseAudio socket.
  ws.on('message', () => {});

  ws.on('close', (code, reason) => {
    logger.info("Audio WebSocket closed", { ...logCtx, code, reason: reason?.toString() });
    cleanupConnection('ws_closed');
  });

  ws.on('error', (err) => {
    logger.error("Audio WebSocket error", { ...logCtx, error: err.message });
    cleanupConnection('ws_error');
  });
}

// --- WebSocket Support for VNC ---
// VNC WebSocket server for handling VNC connections
const vncWss = new WebSocketServer({ noServer: true });
vncWss.on("error", (err) => {
  logger.error("VNC WebSocket server error", { error: err.message });
});

// Guest audio WebSocket server (one-way PCM out of the emulator pods)
const audioWss = new WebSocketServer({ noServer: true });
audioWss.on("error", (err) => {
  logger.error("Audio WebSocket server error", { error: err.message });
});

// WebSocket server for active focus updates
const activeWss = new WebSocketServer({ noServer: true });
let activeWsConnections = 0;
let activeVncConnections = 0;

// WebSocket server for WebRTC signaling
const signalWss = new WebSocketServer({ noServer: true });
signalWss.on("error", (err) => {
  logger.error("Signal WebSocket server error", { error: err.message });
});

// --- Loco Lens (M5Stack watch) WebSocket + REST ---
const { registerWatchRoutes, handleLensConnection } = require("./routes/watch");
const lensWss = new WebSocketServer({ noServer: true });
lensWss.on("error", (err) => logger.error("Lens WebSocket server error", { error: err.message }));

// Resolve an instance id to a VNC endpoint for the lens bridge. Uses a static
// registry (LENS_INSTANCES) when set — for the no-cluster case (Android/Termux,
// compose, single host) — otherwise the k8s instance-target path.
const { InstanceResolver } = require("./services/instanceResolver");
const k8sVncResolver = async (instanceId) => {
  const target = await getInstanceTarget(instanceId); // "host:port" or a URL
  if (!target) return null;
  const [host, portStr] = String(target).replace(/^.*\/\//, "").split(":");
  return { host, port: parseInt(portStr, 10) || 5901 };
};
const lensResolver = new InstanceResolver({ k8sResolver: k8sVncResolver });
logger.info("Lens instance resolver", { mode: lensResolver.mode, staticInstances: lensResolver.listStaticInstances() });
async function lensInstanceResolver(instanceId) {
  return lensResolver.resolve(instanceId);
}
registerWatchRoutes(app, {});

// Active peer connections keyed by ID for WebRTC signaling
const peers = new Map();

// ---------- WebSocket heartbeat (server-side) ----------
// Responds to application-level __ping with __pong so clients can detect
// stale connections even through proxies that eat native WS pings.
// Also sends native WS pings; clients that don't respond are terminated.
const WS_HEARTBEAT_INTERVAL = 30000; // 30s

function setupWsHeartbeat(wss, label) {
  const interval = setInterval(() => {
    wss.clients.forEach((ws) => {
      if (ws.isAlive === false) {
        logger.warn(`Terminating stale ${label} WebSocket (no pong)`);
        return ws.terminate();
      }
      ws.isAlive = false;
      ws.ping(); // native WS ping
    });
  }, WS_HEARTBEAT_INTERVAL);

  wss.on('close', () => clearInterval(interval));
}

function initWsAlive(ws) {
  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });
}

/** Handle application-level __ping messages from the client. Returns true if handled. */
function handleAppPing(ws, data) {
  if (data && data.type === '__ping') {
    ws.send(JSON.stringify({ type: '__pong', ts: data.ts }));
    return true;
  }
  return false;
}

setupWsHeartbeat(activeWss, 'active');
setupWsHeartbeat(signalWss, 'signal');

// Handle incoming signal websocket connections for SDP exchange
signalWss.on("connection", (ws, req) => {
  initWsAlive(ws);
  logger.info("Signal WebSocket client connected", { url: req.url });

  let id = null;
  let pc = null;
  // Queue to serialize async message processing (prevents race conditions
  // when register + offer arrive in the same TCP payload)
  let msgQueue = Promise.resolve();

  ws.on("error", (err) => {
    logger.error("Signal WebSocket client error", { error: err.message });
  });

  ws.on("message", (msg) => {
    // Chain each message handler to ensure serial processing
    msgQueue = msgQueue.then(async () => {
      let data;
      try {
        data = JSON.parse(msg);
      } catch (e) {
        logger.error("Invalid JSON in signal message", { error: e.message });
        return;
      }

      // Respond to application-level pings
      if (handleAppPing(ws, data)) return;

      // Handle registration
      if (data.type === "register") {
        id = data.id || Math.random().toString(36).slice(2);
        ws.send(JSON.stringify({ type: "registered", id }));
        logger.info("Signal WebSocket client registered", { id });

        // Initialize PeerConnection (synchronous - no await needed)
        try {
          const iceServers = []; // Fetch from config if needed
          pc = udpToWebrtc.createConnection(iceServers);

          // Handle ICE candidates from Backend -> Frontend
          // NOTE: werift uses pc.onIceCandidate.subscribe() not pc.onicecandidate
          pc.onIceCandidate.subscribe((candidate) => {
            const candidateJson = candidate.toJSON ? candidate.toJSON() : candidate;
            ws.send(JSON.stringify({
              type: "signal",
              data: candidateJson
            }));
            logger.debug("Sent ICE candidate to client", { id, sdpMid: candidateJson.sdpMid });
          });

          logger.info("Initialized WebRTC PeerConnection for client", { id });
        } catch (err) {
          logger.error("Failed to create PeerConnection", { error: err.message });
        }
        return;
      }

      // Handle signaling
      if (data.type === "signal" && data.data && pc) {
        const signal = data.data;

        try {
          if (signal.sdp) {
            logger.info("Received SDP", { type: signal.type, id });
            await pc.setRemoteDescription(signal);
            if (signal.type === 'offer') {
              const answer = await pc.createAnswer();
              await pc.setLocalDescription(answer);
              ws.send(JSON.stringify({
                type: "signal",
                data: pc.localDescription
              }));
              logger.info("Sent SDP Answer", { id });
            }
          } else if (signal.candidate) {
            logger.info("Received ICE Candidate", { id });
            // Pass the full candidate object (with sdpMid, sdpMLineIndex) to werift
            await pc.addIceCandidate(signal);
          }
        } catch (err) {
          logger.error("Signaling error", { error: err.message, id });
        }
      }
    }).catch(err => {
      logger.error("Message processing error", { error: err.message, id });
    });
  });

  ws.on("close", () => {
    if (pc) {
      pc.close();
      logger.info("Closed PeerConnection", { id });
    }
    logger.info("Signal WebSocket client disconnected", { id });
  });
});

activeWss.on("connection", (ws) => {
  initWsAlive(ws);
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
      // Respond to application-level pings
      if (handleAppPing(ws, data)) return;
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

  // Guest audio: /proxy/audio/:instanceId — tested BEFORE the VNC match so a
  // future loosening of that pattern can never shadow this one. nginx already
  // forwards all of /proxy/ with upgrade headers, so no config change there.
  const audioMatch = req.url.match(/^\/proxy\/audio\/([^\/\?]+)/);
  if (audioMatch) {
    const instanceId = audioMatch[1];
    const query = url.parse(req.url, true).query;
    const traceId = query.traceId || `gen-${Date.now()}`;

    logger.info("Audio Upgrade Request", { instanceId, traceId, url: req.url });

    getInstanceTarget(instanceId).then(target => {
      if (target) {
        audioWss.handleUpgrade(req, socket, head, (ws) => {
          createAudioBridge(ws, target, instanceId, traceId);
        });
      } else {
        logger.error("Audio WebSocket proxy: Unknown instance", { instanceId });
        socket.destroy();
      }
    }).catch(error => {
      logger.error("Audio WebSocket proxy error", { instanceId, error: error.message });
      socket.destroy();
    });

    return;
  }

  // Match VNC proxy URLs
  // /proxy/vnc/:instanceId?traceId=...
  const vncMatch = req.url.match(/^\/proxy\/vnc\/([^\/\?]+)/);
  if (vncMatch) {
    const instanceId = vncMatch[1];
    const query = url.parse(req.url, true).query;
    const traceId = query.traceId || `gen-${Date.now()}`;

    logger.info("VNC Upgrade Request", { instanceId, traceId, url: req.url });

    getInstanceTarget(instanceId).then(target => {
      if (target) {
        logger.info("VNC WebSocket proxy established", { instanceId, target, traceId });

        // Use the VNC WebSocket server
        vncWss.handleUpgrade(req, socket, head, (ws) => {
          createVNCBridge(ws, target, instanceId, traceId);
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

  // Loco Lens WebSocket (M5Stack watch): /ws/lens/:instanceId
  const lensMatch = req.url.match(/^\/ws\/lens\/([^\/\?]+)/);
  if (lensMatch) {
    lensWss.handleUpgrade(req, socket, head, (ws) => {
      handleLensConnection(ws, decodeURIComponent(lensMatch[1]), lensInstanceResolver);
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

  // WebRTC signaling WebSocket
  if (req.url.startsWith('/signal')) {
    signalWss.handleUpgrade(req, socket, head, (ws) => {
      signalWss.emit('connection', ws, req);
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
  // qualityMonitor.start();

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
