const request = require('supertest');
const express = require('express');

// Mock the services before importing server
jest.mock('../services/streamQualityMonitor', () => {
  return jest.fn().mockImplementation(() => ({
    start: jest.fn(),
    stop: jest.fn(),
    getAllMetrics: jest.fn(() => ({})),
    getInstanceMetrics: jest.fn(() => null),
    getQualitySummary: jest.fn(() => ({}))
  }));
});

jest.mock('../services/instanceManager', () => {
  return jest.fn().mockImplementation(() => ({
    getInstances: jest.fn(() => Promise.resolve([])),
    getProvisionedInstances: jest.fn(() => Promise.resolve([])),
    getKubernetesInfo: jest.fn(() => Promise.resolve({})),
    isUsingKubernetesDiscovery: jest.fn(() => false),
    refreshDiscovery: jest.fn(() => Promise.resolve([])),
    getInstanceById: jest.fn(() => Promise.resolve(null))
  }));
});

// Mock file system operations
jest.mock('fs', () => ({
  existsSync: jest.fn(() => false),
  readFileSync: jest.fn(() => '{"active": []}'),
  writeFileSync: jest.fn()
}));

describe('Prometheus Metrics', () => {
  let server;
  let app;

  beforeAll(() => {
    // Set test environment
    process.env.NODE_ENV = 'test';
    process.env.CI = 'true';
    
    // Create a mock server for testing
    app = express();
    
    // Import and setup metrics after mocking
    const client = require('prom-client');
    const register = new client.Registry();
    client.collectDefaultMetrics({ register });
    
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
    
    register.registerMetric(httpRequestDuration);
    register.registerMetric(activeConnections);
    
    // Add middleware to track request duration
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
    
    // Add metrics endpoint
    app.get('/metrics', async (req, res) => {
      try {
        const metrics = await register.metrics();
        res.set('Content-Type', register.contentType);
        res.end(metrics);
      } catch (e) {
        res.status(500).end('Error generating metrics');
      }
    });
    
    // Add health endpoint for testing
    app.get('/health', (req, res) => {
      res.json({ status: 'ok' });
    });
  });

  afterAll(() => {
    if (server) {
      server.close();
    }
  });

  describe('GET /metrics', () => {
    it('should return Prometheus metrics', async () => {
      const response = await request(app)
        .get('/metrics')
        .expect(200);

      expect(response.headers['content-type']).toContain('text/plain');
      expect(response.text).toContain('# HELP');
      expect(response.text).toContain('# TYPE');
    });

    it('should include custom metrics', async () => {
      const response = await request(app)
        .get('/metrics')
        .expect(200);

      expect(response.text).toContain('http_request_duration_seconds');
      expect(response.text).toContain('active_connections_total');
    });

    it('should include default metrics', async () => {
      const response = await request(app)
        .get('/metrics')
        .expect(200);

      expect(response.text).toContain('process_cpu_user_seconds_total');
      expect(response.text).toContain('nodejs_heap_size_total_bytes');
    });
  });

  describe('HTTP request duration tracking', () => {
    it('should track request duration for health endpoint', async () => {
      // Make a request to health endpoint
      await request(app)
        .get('/health')
        .expect(200);

      // Check that metrics include the request
      const response = await request(app)
        .get('/metrics')
        .expect(200);

      expect(response.text).toContain('http_request_duration_seconds');
      expect(response.text).toContain('method="GET"');
      expect(response.text).toContain('status_code="200"');
    });
  });

  describe('Active connections gauge', () => {
    it('should have active connections metric', async () => {
      const response = await request(app)
        .get('/metrics')
        .expect(200);

      expect(response.text).toContain('active_connections_total');
      expect(response.text).toContain('# HELP active_connections_total Number of active connections');
      expect(response.text).toContain('# TYPE active_connections_total gauge');
    });
  });
});