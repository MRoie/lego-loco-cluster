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

// Import after mocking
const InstanceManager = require('../services/instanceManager');

// Mock the config directory
const mockConfigDir = '/tmp/test-config';

// Create test config directory and instances.json
beforeAll(() => {
  if (!fs.existsSync(mockConfigDir)) {
    fs.mkdirSync(mockConfigDir, { recursive: true });
  }
  
  const mockInstances = [
    {
      "id": "instance-0",
      "streamUrl": "http://localhost:6080/vnc0",
      "vncUrl": "loco-emulator-0:5901",
      "healthUrl": "http://loco-emulator-0:8080",
      "name": "Windows 98 - Game Server",
      "provisioned": true,
      "ready": false,
      "status": "booting"
    },
    {
      "id": "instance-1",
      "streamUrl": "http://localhost:6081/vnc1",
      "vncUrl": "loco-emulator-1:5901",
      "healthUrl": "http://loco-emulator-1:8080",
      "name": "Windows 98 - Client 1",
      "provisioned": true,
      "ready": true,
      "status": "ready"
    }
  ];
  
  fs.writeFileSync(
    `${mockConfigDir}/instances.json`,
    JSON.stringify(mockInstances, null, 2)
  );
  
  const mockStatus = {
    "instance-0": "booting",
    "instance-1": "ready"
  };
  
  fs.writeFileSync(
    `${mockConfigDir}/status.json`,
    JSON.stringify(mockStatus, null, 2)
  );
});

afterAll(() => {
  // Clean up test files
  fs.rmSync(mockConfigDir, { recursive: true, force: true });
});

describe('InstanceManager', () => {
  let instanceManager;

  beforeEach(() => {
    instanceManager = new InstanceManager(mockConfigDir);
  });

  test('should load static instances when Kubernetes is not available', async () => {
    const instances = await instanceManager.getInstances();
    
    expect(instances).toHaveLength(2);
    expect(instances[0].id).toBe('instance-0');
    expect(instances[1].id).toBe('instance-1');
  });

  test('should get provisioned instances correctly', async () => {
    const provisionedInstances = await instanceManager.getProvisionedInstances();
    
    // Should include both instances since they are marked as provisioned
    expect(provisionedInstances.length).toBeGreaterThan(0);
    expect(provisionedInstances.every(inst => inst.provisioned)).toBe(true);
  });

  test('should find instance by ID', async () => {
    const instance = await instanceManager.getInstanceById('instance-0');
    
    expect(instance).toBeDefined();
    expect(instance.id).toBe('instance-0');
    expect(instance.name).toBe('Windows 98 - Game Server');
  });

  test('should return null for non-existent instance', async () => {
    const instance = await instanceManager.getInstanceById('non-existent');
    
    expect(instance).toBeUndefined();
  });

  test('should indicate not using Kubernetes discovery when K8s is unavailable', () => {
    expect(instanceManager.isUsingKubernetesDiscovery()).toBe(false);
  });

  test('should refresh discovery and invalidate cache', async () => {
    // Get instances once to populate cache
    await instanceManager.getInstances();
    
    // Refresh discovery
    const refreshedInstances = await instanceManager.refreshDiscovery();
    
    expect(refreshedInstances).toHaveLength(2);
  });

  test('should handle missing config files gracefully', async () => {
    const badInstanceManager = new InstanceManager('/non-existent-dir');
    const instances = await badInstanceManager.getInstances();
    
    expect(instances).toEqual([]);
  });
});

describe('Instance Manager API Endpoints', () => {
  let app;
  let instanceManager;

  beforeAll(() => {
    // Create a test Express app with the instance manager endpoints
    app = express();
    app.use(express.json());
    
    instanceManager = new InstanceManager(mockConfigDir);

    // Add the endpoints we created
    app.get('/api/instances', async (req, res) => {
      try {
        const instances = await instanceManager.getInstances();
        res.json(instances);
      } catch (e) {
        res.status(503).json([]);
      }
    });

    app.get('/api/instances/provisioned', async (req, res) => {
      try {
        const provisionedInstances = await instanceManager.getProvisionedInstances();
        res.json(provisionedInstances);
      } catch (e) {
        res.status(503).json([]);
      }
    });

    app.get('/api/instances/discovery-info', async (req, res) => {
      try {
        const k8sInfo = await instanceManager.getKubernetesInfo();
        const isUsingK8sDiscovery = instanceManager.isUsingKubernetesDiscovery();
        
        res.json({
          kubernetesDiscovery: k8sInfo,
          usingAutoDiscovery: isUsingK8sDiscovery,
          fallbackToStatic: !isUsingK8sDiscovery
        });
      } catch (e) {
        res.status(500).json({ error: "Failed to get discovery info" });
      }
    });

    app.post('/api/instances/refresh', async (req, res) => {
      try {
        const instances = await instanceManager.refreshDiscovery();
        res.json({
          message: "Discovery refreshed successfully",
          instanceCount: instances.length,
          instances: instances
        });
      } catch (e) {
        res.status(500).json({ error: "Failed to refresh discovery" });
      }
    });
  });

  test('GET /api/instances should return all instances', async () => {
    const response = await request(app).get('/api/instances');
    
    expect(response.status).toBe(200);
    expect(response.body).toHaveLength(2);
    expect(response.body[0].id).toBe('instance-0');
  });

  test('GET /api/instances/provisioned should return only provisioned instances', async () => {
    const response = await request(app).get('/api/instances/provisioned');
    
    expect(response.status).toBe(200);
    expect(response.body.length).toBeGreaterThan(0);
    expect(response.body.every(inst => inst.provisioned)).toBe(true);
  });

  test('GET /api/instances/discovery-info should return discovery status', async () => {
    const response = await request(app).get('/api/instances/discovery-info');
    
    expect(response.status).toBe(200);
    expect(response.body.usingAutoDiscovery).toBe(false);
    expect(response.body.fallbackToStatic).toBe(true);
  });

  test('POST /api/instances/refresh should refresh discovery', async () => {
    const response = await request(app).post('/api/instances/refresh');
    
    expect(response.status).toBe(200);
    expect(response.body.message).toBe("Discovery refreshed successfully");
    expect(response.body.instanceCount).toBe(2);
  });
});