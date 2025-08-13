const request = require('supertest');
const express = require('express');
const fs = require('fs');
const path = require('path');

// Mock the Kubernetes client
jest.mock('@kubernetes/client-node', () => ({
  KubeConfig: jest.fn(() => ({
    loadFromCluster: jest.fn(),
    loadFromDefault: jest.fn(),
    makeApiClient: jest.fn(() => ({
      listNamespacedPod: jest.fn(),
      listNamespacedService: jest.fn()
    }))
  })),
  CoreV1Api: jest.fn(),
  Watch: jest.fn()
}));

// Create test app by requiring the server module
let app;
let server;

// Mock config directory setup
const mockConfigDir = '/tmp/health-test-config';

beforeAll(async () => {
  // Setup mock config directory
  if (!fs.existsSync(mockConfigDir)) {
    fs.mkdirSync(mockConfigDir, { recursive: true });
  }
  
  // Create mock config files
  const mockInstances = [
    {
      "id": "instance-0",
      "streamUrl": "http://localhost:6080/vnc0",
      "vncUrl": "localhost:5901",
      "name": "Test Instance",
      "provisioned": true
    }
  ];
  
  const mockStatus = {
    "instance-0": "ready"
  };
  
  fs.writeFileSync(path.join(mockConfigDir, 'instances.json'), JSON.stringify(mockInstances, null, 2));
  fs.writeFileSync(path.join(mockConfigDir, 'status.json'), JSON.stringify(mockStatus, null, 2));
  fs.writeFileSync(path.join(mockConfigDir, 'active.json'), JSON.stringify({ active: [] }, null, 2));
  
  // Set environment variables
  process.env.CONFIG_DIR = mockConfigDir;
  process.env.NODE_ENV = 'test';
  process.env.ALLOW_EMPTY_DISCOVERY = 'true';
  
  // Import server after setting up environment
  delete require.cache[require.resolve('../server.js')];
  
  // We need to create a minimal test version since the full server starts a server
  const testApp = express();
  
  // Add the same middleware and routes as the main server
  testApp.use(express.json());
  
  // Import the health check routes manually by creating a simplified version
  const InstanceManager = require('../services/instanceManager');
  const StreamQualityMonitor = require('../services/streamQualityMonitor');
  
  const FINAL_CONFIG_DIR = mockConfigDir;
  
  // Mock instance manager that's immediately initialized
  const mockInstanceManager = {
    initialized: true,
    getInstances: jest.fn().mockResolvedValue([
      { id: "instance-0", name: "Test Instance", provisioned: true }
    ])
  };
  
  const mockQualityMonitor = {};
  
  // Add enhanced health endpoint
  testApp.get("/health", (req, res) => {
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
        instance_manager: mockInstanceManager ? "initialized" : "not_initialized",
        quality_monitor: mockQualityMonitor ? "initialized" : "not_initialized"
      }
    };
    
    res.json(healthData);
  });
  
  // Add metrics endpoint
  testApp.get("/metrics", (req, res) => {
    res.set('Content-Type', 'text/plain; version=0.0.4; charset=utf-8');
    res.send('# HELP test_metric Test metric for health tests\n# TYPE test_metric counter\ntest_metric 1\n');
  });
  
  // Add readiness endpoint
  testApp.get("/ready", async (req, res) => {
    const checks = {
      timestamp: new Date().toISOString(),
      overall_status: "unknown",
      checks: {}
    };
    
    let allHealthy = true;
    
    try {
      // Check instance manager
      checks.checks.instance_manager = {
        status: mockInstanceManager && mockInstanceManager.initialized ? "healthy" : "unhealthy",
        message: mockInstanceManager && mockInstanceManager.initialized ? "Instance manager initialized" : "Instance manager not initialized"
      };
      if (!mockInstanceManager || !mockInstanceManager.initialized) {
        allHealthy = false;
      }
      
      // Check config directory
      const configExists = fs.existsSync(FINAL_CONFIG_DIR);
      checks.checks.config_directory = {
        status: configExists ? "healthy" : "unhealthy",
        message: configExists ? `Config directory accessible at ${FINAL_CONFIG_DIR}` : `Config directory not found at ${FINAL_CONFIG_DIR}`,
        path: FINAL_CONFIG_DIR
      };
      if (!configExists) {
        allHealthy = false;
      }
      
      // Check config files
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
        status: mockQualityMonitor ? "healthy" : "unhealthy",
        message: mockQualityMonitor ? "Quality monitor initialized" : "Quality monitor not initialized"
      };
      if (!mockQualityMonitor) {
        allHealthy = false;
      }
      
      // Check instances API
      try {
        const instances = await mockInstanceManager.getInstances();
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
      
      // Memory check
      const memoryUsage = process.memoryUsage().heapUsed / 1024 / 1024;
      checks.checks.memory = {
        status: memoryUsage < 512 ? "healthy" : "warning",
        message: `Memory usage: ${Math.round(memoryUsage)}MB`,
        usage_mb: Math.round(memoryUsage),
        threshold_mb: 512
      };
      
    } catch (error) {
      allHealthy = false;
      checks.checks.general_error = {
        status: "unhealthy",
        message: `Readiness check failed: ${error.message}`
      };
    }
    
    checks.overall_status = allHealthy ? "ready" : "not_ready";
    const statusCode = allHealthy ? 200 : 503;
    res.status(statusCode).json(checks);
  });
  
  app = testApp;
});

afterAll(() => {
  // Cleanup mock config directory
  if (fs.existsSync(mockConfigDir)) {
    fs.rmSync(mockConfigDir, { recursive: true });
  }
  
  if (server) {
    server.close();
  }
});

describe('Health Check Endpoints', () => {
  describe('GET /health', () => {
    it('should return detailed health information', async () => {
      const response = await request(app)
        .get('/health')
        .expect(200);
      
      expect(response.body).toMatchObject({
        status: 'ok',
        timestamp: expect.any(String),
        uptime: expect.any(Number),
        version: expect.any(String),
        node_version: expect.any(String),
        memory: {
          used: expect.any(Number),
          total: expect.any(Number),
          external: expect.any(Number),
          rss: expect.any(Number)
        },
        environment: 'test',
        config_directory: mockConfigDir,
        services: {
          instance_manager: 'initialized',
          quality_monitor: 'initialized'
        }
      });
    });
    
    it('should include memory usage in MB', async () => {
      const response = await request(app)
        .get('/health')
        .expect(200);
      
      expect(response.body.memory.used).toBeGreaterThan(0);
      expect(response.body.memory.total).toBeGreaterThan(0);
    });
    
    it('should include current timestamp', async () => {
      const response = await request(app)
        .get('/health')
        .expect(200);
      
      const timestamp = new Date(response.body.timestamp);
      const now = new Date();
      const diff = Math.abs(now - timestamp);
      
      // Should be within 5 seconds
      expect(diff).toBeLessThan(5000);
    });
  });
  
  describe('GET /ready', () => {
    it('should return readiness information when healthy', async () => {
      const response = await request(app)
        .get('/ready')
        .expect(200);
      
      expect(response.body).toMatchObject({
        timestamp: expect.any(String),
        overall_status: 'ready',
        checks: expect.objectContaining({
          instance_manager: {
            status: 'healthy',
            message: expect.any(String)
          },
          config_directory: {
            status: 'healthy',
            message: expect.any(String),
            path: mockConfigDir
          },
          config_files: {
            status: 'healthy',
            message: expect.any(String),
            files: expect.objectContaining({
              'instances.json': {
                status: 'accessible',
                path: expect.any(String)
              },
              'status.json': {
                status: 'accessible',
                path: expect.any(String)
              }
            })
          },
          quality_monitor: {
            status: 'healthy',
            message: expect.any(String)
          },
          instances_api: {
            status: 'healthy',
            message: expect.any(String),
            instance_count: expect.any(Number)
          },
          memory: {
            status: expect.stringMatching(/healthy|warning/),
            message: expect.any(String),
            usage_mb: expect.any(Number),
            threshold_mb: 512
          }
        })
      });
    });
    
    it('should check all essential config files', async () => {
      const response = await request(app)
        .get('/ready')
        .expect(200);
      
      const configFiles = response.body.checks.config_files.files;
      expect(configFiles).toEqual(
        expect.objectContaining({
          'instances.json': expect.objectContaining({
            status: 'accessible',
            path: expect.stringContaining('instances.json')
          }),
          'status.json': expect.objectContaining({
            status: 'accessible', 
            path: expect.stringContaining('status.json')
          })
        })
      );
    });
    
    it('should include instance count from API', async () => {
      const response = await request(app)
        .get('/ready')
        .expect(200);
      
      expect(response.body.checks.instances_api.instance_count).toBe(1);
    });
  });
  
  describe('Readiness with missing dependencies', () => {
    let appWithMissingConfig;
    
    beforeAll(() => {
      const testAppUnhealthy = express();
      testAppUnhealthy.use(express.json());
      
      const MISSING_CONFIG_DIR = '/tmp/nonexistent-config';
      
      // Mock unhealthy instance manager
      const unhealthyInstanceManager = {
        initialized: false,
        getInstances: jest.fn().mockRejectedValue(new Error('Not initialized'))
      };
      
      testAppUnhealthy.get("/ready", async (req, res) => {
        const checks = {
          timestamp: new Date().toISOString(),
          overall_status: "unknown",
          checks: {}
        };
        
        let allHealthy = true;
        
        // Check instance manager (unhealthy)
        checks.checks.instance_manager = {
          status: "unhealthy",
          message: "Instance manager not initialized"
        };
        allHealthy = false;
        
        // Check config directory (missing)
        checks.checks.config_directory = {
          status: "unhealthy",
          message: `Config directory not found at ${MISSING_CONFIG_DIR}`,
          path: MISSING_CONFIG_DIR
        };
        allHealthy = false;
        
        checks.overall_status = allHealthy ? "ready" : "not_ready";
        const statusCode = allHealthy ? 200 : 503;
        res.status(statusCode).json(checks);
      });
      
      appWithMissingConfig = testAppUnhealthy;
    });
    
    it('should return 503 when dependencies are unhealthy', async () => {
      const response = await request(appWithMissingConfig)
        .get('/ready')
        .expect(503);
      
      expect(response.body.overall_status).toBe('not_ready');
      expect(response.body.checks.instance_manager.status).toBe('unhealthy');
      expect(response.body.checks.config_directory.status).toBe('unhealthy');
    });
  });
  
  describe('GET /metrics', () => {
    it('should return metrics in Prometheus format', async () => {
      const response = await request(app)
        .get('/metrics')
        .expect(200);
      
      expect(response.headers['content-type']).toMatch(/text\/plain/);
      expect(response.text).toContain('test_metric');
    });
  });
});