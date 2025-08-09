const { describe, it, expect, beforeEach, afterEach } = require('@jest/globals');
const StreamQualityMonitor = require('../services/streamQualityMonitor');
const fs = require('fs');
const path = require('path');
const { WebSocketServer } = require('ws');
const http = require('http');

describe('StreamQualityMonitor - Audio and Controls Testing', () => {
  let monitor;
  let testServer;
  let wss;
  let testConfigDir;

  beforeEach(async () => {
    // Create temporary config directory
    testConfigDir = path.join(__dirname, 'tmp_config');
    if (!fs.existsSync(testConfigDir)) {
      fs.mkdirSync(testConfigDir, { recursive: true });
    }

    // Create test instances config
    const testInstances = [
      {
        id: 'test-instance-1',
        name: 'Test Instance 1',
        vncUrl: 'localhost:5901',
        streamUrl: 'localhost:5901'
      },
      {
        id: 'test-instance-2',
        name: 'Test Instance 2',
        vncUrl: 'localhost:5902',
        streamUrl: 'localhost:5902'
      }
    ];

    fs.writeFileSync(
      path.join(testConfigDir, 'instances.json'),
      JSON.stringify(testInstances, null, 2)
    );

    monitor = new StreamQualityMonitor(testConfigDir);

    // Create test WebSocket server to simulate VNC proxy
    testServer = http.createServer();
    wss = new WebSocketServer({ server: testServer });

    // Set up WebSocket handler to simulate VNC responses
    wss.on('connection', (ws, request) => {
      const url = request.url;
      console.log('Test WebSocket connection:', url);

      // Simulate VNC handshake
      ws.on('message', (data) => {
        console.log('Received VNC message:', data.toString());
        
        // Simulate VNC server response
        if (data.toString().includes('RFB')) {
          // Send back VNC version response
          ws.send(Buffer.from('RFB 003.008\n'));
          
          // Simulate successful handshake
          setTimeout(() => {
            ws.send(Buffer.from([0x01])); // Success
          }, 100);
        }
      });

      // Simulate some VNC activity for audio/video testing
      const simulateActivity = () => {
        if (ws.readyState === ws.OPEN) {
          // Simulate frame buffer updates (video)
          ws.send(Buffer.from([0x00, 0x00, 0x00, 0x01])); // Frame buffer update
          
          // Simulate audio data
          ws.send(Buffer.from([0x02, 0x00, 0x00, 0x01])); // Audio data
        }
      };

      // Send periodic updates to simulate active stream
      const activityInterval = setInterval(simulateActivity, 200);

      ws.on('close', () => {
        clearInterval(activityInterval);
      });
    });

    // Start test server
    await new Promise((resolve) => {
      testServer.listen(3001, resolve);
    });
  });

  afterEach(async () => {
    // Stop monitoring first
    if (monitor) {
      monitor.stop();
      // Wait a bit for cleanup
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    
    if (testServer) {
      await new Promise((resolve) => {
        testServer.close(() => {
          // Wait for server to fully close
          setTimeout(resolve, 50);
        });
      });
    }

    // Clean up test config
    if (fs.existsSync(testConfigDir)) {
      fs.rmSync(testConfigDir, { recursive: true, force: true });
    }
  });

  describe('Audio Testing', () => {
    it('should detect audio availability', async () => {
      await monitor.probeAllInstances();
      const metrics = monitor.getAllMetrics();
      
      expect(Object.keys(metrics)).toHaveLength(2);
      
      for (const [instanceId, instanceMetrics] of Object.entries(metrics)) {
        expect(instanceMetrics).toHaveProperty('availability.audio');
        expect(instanceMetrics).toHaveProperty('quality.audioLevel');
        expect(instanceMetrics).toHaveProperty('quality.audioQuality');
        
        // Audio should be detected if VNC is available
        if (instanceMetrics.availability.vnc) {
          expect(instanceMetrics.availability.audio).toBe(true);
          expect(instanceMetrics.quality.audioLevel).toBeGreaterThan(0);
          expect(['excellent', 'good', 'fair', 'poor']).toContain(instanceMetrics.quality.audioQuality);
        }
      }
    });

    it('should measure audio quality levels', async () => {
      await monitor.probeAllInstances();
      const metrics = monitor.getAllMetrics();
      
      for (const [instanceId, instanceMetrics] of Object.entries(metrics)) {
        if (instanceMetrics.availability.audio) {
          expect(instanceMetrics.quality.audioLevel).toBeGreaterThanOrEqual(0);
          expect(instanceMetrics.quality.audioLevel).toBeLessThanOrEqual(1);
        }
      }
    });

    it('should categorize audio quality correctly', async () => {
      await monitor.probeAllInstances();
      const metrics = monitor.getAllMetrics();
      
      for (const [instanceId, instanceMetrics] of Object.entries(metrics)) {
        const audioQuality = instanceMetrics.quality.audioQuality;
        expect(['excellent', 'good', 'fair', 'poor', 'error', 'unavailable', 'unknown']).toContain(audioQuality);
        
        // Quality should correlate with latency
        if (instanceMetrics.quality.connectionLatency !== null && instanceMetrics.availability.audio) {
          const latency = instanceMetrics.quality.connectionLatency;
          
          if (latency < 50) {
            expect(['excellent', 'good']).toContain(audioQuality);
          } else if (latency > 200) {
            expect(['poor', 'fair']).toContain(audioQuality);
          }
        }
      }
    });
  });

  describe('Controls Testing', () => {
    it('should test VNC control responsiveness', async () => {
      await monitor.probeAllInstances();
      const metrics = monitor.getAllMetrics();
      
      for (const [instanceId, instanceMetrics] of Object.entries(metrics)) {
        expect(instanceMetrics).toHaveProperty('availability.controls');
        expect(instanceMetrics).toHaveProperty('quality.controlsResponsive');
        
        // Controls should be responsive if VNC is available
        if (instanceMetrics.availability.vnc) {
          expect(instanceMetrics.availability.controls).toBe(true);
          expect(instanceMetrics.quality.controlsResponsive).toBe(true);
        }
      }
    });

    it('should detect control failures', async () => {
      // Stop the test server to simulate control failures
      await new Promise((resolve) => {
        testServer.close(resolve);
      });

      await monitor.probeAllInstances();
      const metrics = monitor.getAllMetrics();
      
      for (const [instanceId, instanceMetrics] of Object.entries(metrics)) {
        // With server down, controls should not be responsive
        expect(instanceMetrics.availability.controls).toBe(false);
        expect(instanceMetrics.quality.controlsResponsive).toBe(false);
      }
    });

    it('should handle partial functionality correctly', async () => {
      // Test scenario where VNC is available but controls are unresponsive
      await monitor.probeAllInstances();
      const metrics = monitor.getAllMetrics();
      
      for (const [instanceId, instanceMetrics] of Object.entries(metrics)) {
        // Verify that audio and controls are tested independently
        if (instanceMetrics.availability.audio && !instanceMetrics.quality.controlsResponsive) {
          expect(instanceMetrics.quality.audioQuality).toBe('fair');
        } else if (!instanceMetrics.availability.audio && instanceMetrics.quality.controlsResponsive) {
          expect(instanceMetrics.quality.audioQuality).toBe('poor');
        } else if (!instanceMetrics.availability.audio && !instanceMetrics.quality.controlsResponsive) {
          expect(instanceMetrics.quality.audioQuality).toBe('error');
        }
      }
    });
  });

  describe('Comprehensive Quality Assessment', () => {
    it('should provide complete quality metrics', async () => {
      await monitor.probeAllInstances();
      const metrics = monitor.getAllMetrics();
      
      for (const [instanceId, instanceMetrics] of Object.entries(metrics)) {
        // Verify all required fields are present
        expect(instanceMetrics).toHaveProperty('instanceId', instanceId);
        expect(instanceMetrics).toHaveProperty('timestamp');
        
        // Availability checks
        expect(instanceMetrics.availability).toHaveProperty('vnc');
        expect(instanceMetrics.availability).toHaveProperty('stream');
        expect(instanceMetrics.availability).toHaveProperty('audio');
        expect(instanceMetrics.availability).toHaveProperty('controls');
        
        // Quality metrics
        expect(instanceMetrics.quality).toHaveProperty('connectionLatency');
        expect(instanceMetrics.quality).toHaveProperty('videoFrameRate');
        expect(instanceMetrics.quality).toHaveProperty('audioQuality');
        expect(instanceMetrics.quality).toHaveProperty('audioLevel');
        expect(instanceMetrics.quality).toHaveProperty('controlsResponsive');
        expect(instanceMetrics.quality).toHaveProperty('packetLoss');
        expect(instanceMetrics.quality).toHaveProperty('jitter');
        
        // Error tracking
        expect(instanceMetrics).toHaveProperty('errors');
        expect(Array.isArray(instanceMetrics.errors)).toBe(true);
      }
    });

    it('should generate quality summary correctly', async () => {
      await monitor.probeAllInstances();
      const summary = monitor.getQualitySummary();
      
      expect(summary).toHaveProperty('total');
      expect(summary).toHaveProperty('available');
      expect(summary).toHaveProperty('availabilityPercent');
      expect(summary).toHaveProperty('averageLatency');
      expect(summary).toHaveProperty('qualityDistribution');
      
      expect(summary.total).toBe(2); // Two test instances
      expect(summary.availabilityPercent).toBeGreaterThanOrEqual(0);
      expect(summary.availabilityPercent).toBeLessThanOrEqual(100);
      
      // Quality distribution should be an object with quality levels
      expect(typeof summary.qualityDistribution).toBe('object');
    });

    it('should handle monitoring lifecycle correctly', async () => {
      expect(monitor.isRunning).toBe(false);
      
      monitor.start();
      expect(monitor.isRunning).toBe(true);
      
      // Wait for initial probe
      await new Promise(resolve => setTimeout(resolve, 100));
      
      const metrics = monitor.getAllMetrics();
      expect(Object.keys(metrics).length).toBeGreaterThan(0);
      
      monitor.stop();
      expect(monitor.isRunning).toBe(false);
    });
  });

  describe('Error Handling', () => {
    it('should handle configuration errors gracefully', () => {
      const badConfigMonitor = new StreamQualityMonitor('/nonexistent/path');
      const instances = badConfigMonitor.loadInstances();
      expect(instances).toEqual([]);
    });

    it('should handle network errors gracefully', async () => {
      // Create monitor with invalid host
      const testInstancesInvalid = [
        {
          id: 'invalid-instance',
          name: 'Invalid Instance',
          vncUrl: 'invalid-host:9999',
          streamUrl: 'invalid-host:9999'
        }
      ];

      fs.writeFileSync(
        path.join(testConfigDir, 'instances.json'),
        JSON.stringify(testInstancesInvalid, null, 2)
      );

      const badMonitor = new StreamQualityMonitor(testConfigDir);
      await badMonitor.probeAllInstances();
      
      const metrics = badMonitor.getAllMetrics();
      const invalidMetrics = metrics['invalid-instance'];
      
      expect(invalidMetrics).toBeDefined();
      expect(invalidMetrics.availability.vnc).toBe(false);
      expect(invalidMetrics.quality.audioQuality).toBe('error');
      expect(invalidMetrics.errors.length).toBeGreaterThan(0);
    });
  });
});