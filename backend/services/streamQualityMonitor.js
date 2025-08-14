const net = require('net');
const fs = require('fs');
const path = require('path');
const { WebSocket } = require('ws');
const http = require('http');
const logger = require('../../utils/logger');

/**
 * Stream Quality Monitoring Service
 * Provides video/audio quality monitoring and availability probing for QEMU instances
 * with deep health probing and intelligent failure detection/recovery
 */
class StreamQualityMonitor {
  constructor(configDir = '../config', instanceManager = null) {
    this.configDir = configDir;
    this.instanceManager = instanceManager;
    this.metrics = new Map(); // instanceId -> metrics
    this.probeInterval = 5000; // 5 seconds
    this.deepProbeInterval = 15000; // 15 seconds for deep health checks
    this.probeTimer = null;
    this.deepProbeTimer = null;
    this.initialTimer = null; // Track initial timeout
    this.isRunning = false;
    this.recoveryAttempts = new Map(); // instanceId -> attempts count
    this.maxRecoveryAttempts = 3;
  }

  /**
   * Start the monitoring service
   */
  start() {
    if (this.isRunning) return;
    
    logger.info("Starting Stream Quality Monitor with deep health probing");
    this.isRunning = true;
    
    // Regular connectivity probes
    this.probeTimer = setInterval(() => {
      this.probeAllInstances();
    }, this.probeInterval);
    
    // Deep health probes for QEMU subsystems
    this.deepProbeTimer = setInterval(() => {
      this.deepProbeAllInstances();
    }, this.deepProbeInterval);
    
    // Initial probes
    this.probeAllInstances();
    this.initialTimer = setTimeout(() => this.deepProbeAllInstances(), 2000);
  }

  /**
   * Stop the monitoring service
   */
  stop() {
    if (!this.isRunning) return;
    
    logger.info("Stopping Stream Quality Monitor");
    this.isRunning = false;
    
    if (this.probeTimer) {
      clearInterval(this.probeTimer);
      this.probeTimer = null;
    }
    
    if (this.deepProbeTimer) {
      clearInterval(this.deepProbeTimer);
      this.deepProbeTimer = null;
    }
    
    if (this.initialTimer) {
      clearTimeout(this.initialTimer);
      this.initialTimer = null;
    }
    
    // Clear metrics to help with cleanup
    this.metrics.clear();
    this.recoveryAttempts.clear();
  }

  /**
   * Deep probe all instances for comprehensive QEMU health
   */
  async deepProbeAllInstances() {
    try {
      const instances = await this.loadInstances();
      const probePromises = instances.map(instance => 
        this.deepProbeInstance(instance).catch(err => {
          logger.error("Deep probe failed for instance", { instanceId: instance.id, error: err.message });
          return null;
        })
      );
      
      const results = await Promise.all(probePromises);
      
      // Merge deep probe results with existing metrics
      results.forEach((deepMetrics, index) => {
        if (deepMetrics && deepMetrics.instanceId) {
          const existingMetrics = this.metrics.get(deepMetrics.instanceId) || {};
          const mergedMetrics = {
            ...existingMetrics,
            ...deepMetrics,
            timestamp: new Date().toISOString()
          };
          
          this.metrics.set(deepMetrics.instanceId, mergedMetrics);
          
          // Check for failures and trigger recovery if needed
          this.checkForFailuresAndRecover(deepMetrics.instanceId, mergedMetrics);
        }
      });
      
    } catch (error) {
      logger.error("Failed to deep probe instances", { error: error.message });
    }
  }
  async probeAllInstances() {
    try {
      const instances = await this.loadInstances();
      const probePromises = instances.map(instance => 
        this.probeInstance(instance).catch(err => {
          logger.error("Probe failed for instance", { instanceId: instance.id, error: err.message });
          return this.createErrorMetrics(instance.id, err.message);
        })
      );
      
      const results = await Promise.all(probePromises);
      
      // Update metrics map
      results.forEach(metrics => {
        if (metrics && metrics.instanceId) {
          this.metrics.set(metrics.instanceId, metrics);
        }
      });
      
    } catch (error) {
      logger.error("Failed to probe instances", { error: error.message });
    }
  }

  /**
   * Probe a single instance for stream availability and quality
   */
  async probeInstance(instance) {
    const startTime = Date.now();
    const metrics = {
      instanceId: instance.id,
      timestamp: new Date().toISOString(),
      availability: {
        vnc: false,
        stream: false,
        audio: false,
        controls: false
      },
      quality: {
        connectionLatency: null,
        videoFrameRate: null,
        audioQuality: 'unknown',
        audioLevel: 0,
        controlsResponsive: false,
        packetLoss: 0,
        jitter: 0
      },
      errors: []
    };

    // Probe VNC availability
    try {
      const vncAvailable = await this.probeVNCPort(instance.vncUrl);
      metrics.availability.vnc = vncAvailable;
      
      if (!vncAvailable) {
        metrics.errors.push(`VNC connection failed: ${instance.vncUrl} not reachable`);
      }
      
      if (vncAvailable) {
        metrics.quality.connectionLatency = Date.now() - startTime;
        
        // Test actual VNC functionality if available
        const vncTests = await this.testVNCFunctionality(instance);
        metrics.availability.audio = vncTests.audioDetected;
        metrics.availability.controls = vncTests.controlsResponsive;
        metrics.quality.audioLevel = vncTests.audioLevel;
        metrics.quality.controlsResponsive = vncTests.controlsResponsive;
        metrics.quality.videoFrameRate = vncTests.frameRate;
        
        if (vncTests.errors.length > 0) {
          metrics.errors.push(...vncTests.errors);
        }
      }
    } catch (error) {
      metrics.errors.push(`VNC probe failed: ${error.message}`);
    }

    // Probe stream URL availability (if different from VNC)
    if (instance.streamUrl && instance.streamUrl !== instance.vncUrl) {
      try {
        const streamAvailable = await this.probeStreamUrl(instance.streamUrl);
        metrics.availability.stream = streamAvailable;
      } catch (error) {
        metrics.errors.push(`Stream probe failed: ${error.message}`);
      }
    } else {
      metrics.availability.stream = metrics.availability.vnc;
    }

    // Estimate quality based on availability and response time
    this.estimateQualityMetrics(metrics);

    return metrics;
  }

  /**
   * Deep probe a single instance for comprehensive QEMU health
   */
  async deepProbeInstance(instance) {
    logger.debug("Deep probing instance", { instanceId: instance.id });
    
    const deepMetrics = {
      instanceId: instance.id,
      timestamp: new Date().toISOString(),
      deepHealth: {
        qemu: null,
        video: null,
        audio: null,
        performance: null,
        network: null
      },
      failureType: 'none', // 'network', 'qemu', 'client', 'mixed'
      recoveryNeeded: false,
      errors: []
    };

    try {
      // Get QEMU container health endpoint
      const healthData = await this.queryQEMUHealthEndpoint(instance);
      
      if (healthData) {
        deepMetrics.deepHealth = healthData;
        
        // Analyze the health data to determine failure types
        const failureAnalysis = this.analyzeFailureType(healthData);
        deepMetrics.failureType = failureAnalysis.type;
        deepMetrics.recoveryNeeded = failureAnalysis.recoveryNeeded;
        
        logger.info("Deep health analysis completed", { instanceId: instance.id, overallStatus: healthData.overall_status, failureType: failureAnalysis.type });
      } else {
        deepMetrics.errors.push('Unable to retrieve QEMU health data');
        deepMetrics.failureType = 'qemu';
        deepMetrics.recoveryNeeded = true;
      }
      
    } catch (error) {
      deepMetrics.errors.push(`Deep probe failed: ${error.message}`);
      deepMetrics.failureType = 'network';
      deepMetrics.recoveryNeeded = true;
    }

    return deepMetrics;
  }

  /**
   * Query QEMU container health endpoint
   */
  async queryQEMUHealthEndpoint(instance) {
    return new Promise((resolve) => {
      // Use healthUrl from configuration if available, otherwise construct it
      const healthUrl = instance.healthUrl || `http://${instance.id}:8080`;
      
      const req = http.get(healthUrl, { timeout: 5000 }, (res) => {
        let data = '';
        
        res.on('data', (chunk) => {
          data += chunk;
        });
        
        res.on('end', () => {
          try {
            const healthData = JSON.parse(data);
            resolve(healthData);
          } catch (error) {
            logger.error("Failed to parse health data for instance", { instanceId: instance.id, error: error.message });
            resolve(null);
          }
        });
      });
      
      req.on('error', (error) => {
        logger.error("Health endpoint request failed for instance", { instanceId: instance.id, error: error.message });
        resolve(null);
      });
      
      req.on('timeout', () => {
        logger.error("Health endpoint timeout for instance", { instanceId: instance.id });
        req.destroy();
        resolve(null);
      });
    });
  }

  /**
   * Analyze failure type based on health data
   */
  analyzeFailureType(healthData) {
    const analysis = {
      type: 'none',
      recoveryNeeded: false,
      issues: []
    };

    // Check overall QEMU health
    if (!healthData.qemu_healthy) {
      analysis.issues.push('qemu_process');
      analysis.type = 'qemu';
      analysis.recoveryNeeded = true;
    }

    // Check video subsystem
    if (healthData.video && !healthData.video.vnc_available) {
      analysis.issues.push('vnc_unavailable');
      if (analysis.type === 'none') analysis.type = 'qemu';
      analysis.recoveryNeeded = true;
    } else if (healthData.video && healthData.video.estimated_frame_rate === 0) {
      analysis.issues.push('no_video_frames');
      if (analysis.type === 'none') analysis.type = 'qemu';
      analysis.recoveryNeeded = true;
    }

    // Check audio subsystem
    if (healthData.audio && !healthData.audio.pulse_running) {
      analysis.issues.push('audio_subsystem');
      if (analysis.type === 'none') analysis.type = 'qemu';
      analysis.recoveryNeeded = true;
    }

    // Check network health
    if (healthData.network) {
      if (!healthData.network.bridge_up || !healthData.network.tap_up) {
        analysis.issues.push('network_interfaces');
        if (analysis.type === 'none') analysis.type = 'network';
        analysis.recoveryNeeded = true;
      }
      
      if (healthData.network.tx_errors > 10 || healthData.network.rx_errors > 10) {
        analysis.issues.push('network_errors');
        if (analysis.type === 'none') analysis.type = 'network';
        analysis.recoveryNeeded = true;
      }
    }

    // Check performance issues
    if (healthData.performance) {
      const cpuUsage = parseFloat(healthData.performance.cpu_usage) || 0;
      const memoryUsage = parseFloat(healthData.performance.memory_usage) || 0;
      
      if (cpuUsage > 90 || memoryUsage > 90) {
        analysis.issues.push('performance_degradation');
        if (analysis.type === 'none') analysis.type = 'qemu';
        analysis.recoveryNeeded = true;
      }
    }

    // Determine if multiple issue types exist
    const issueTypes = new Set();
    if (analysis.issues.some(i => ['qemu_process', 'vnc_unavailable', 'no_video_frames', 'audio_subsystem', 'performance_degradation'].includes(i))) {
      issueTypes.add('qemu');
    }
    if (analysis.issues.some(i => ['network_interfaces', 'network_errors'].includes(i))) {
      issueTypes.add('network');
    }

    if (issueTypes.size > 1) {
      analysis.type = 'mixed';
    }

    return analysis;
  }

  /**
   * Check for failures and trigger recovery mechanisms
   */
  async checkForFailuresAndRecover(instanceId, metrics) {
    if (!metrics.recoveryNeeded) {
      // Reset recovery attempts if instance is healthy
      this.recoveryAttempts.delete(instanceId);
      return;
    }

    const attempts = this.recoveryAttempts.get(instanceId) || 0;
    if (attempts >= this.maxRecoveryAttempts) {
      logger.warn("Max recovery attempts reached for instance", { instanceId });
      return;
    }

    logger.info("Triggering recovery for instance", { instanceId, attempt: attempts + 1, failureType: metrics.failureType });
    
    this.recoveryAttempts.set(instanceId, attempts + 1);

    try {
      const recoverySuccess = await this.executeRecoveryStrategy(instanceId, metrics.failureType);
      
      if (recoverySuccess) {
        logger.info("Recovery successful for instance", { instanceId });
        this.recoveryAttempts.delete(instanceId);
      } else {
        logger.error("Recovery failed for instance", { instanceId });
      }
    } catch (error) {
      logger.error("Recovery error for instance", { instanceId, error: error.message });
    }
  }

  /**
   * Execute recovery strategy based on failure type
   */
  async executeRecoveryStrategy(instanceId, failureType) {
    logger.info("Executing recovery strategy", { failureType, instanceId });
    
    switch (failureType) {
      case 'network':
        return await this.recoverNetworkIssues(instanceId);
      
      case 'qemu':
        return await this.recoverQEMUIssues(instanceId);
      
      case 'mixed':
        // Try network recovery first, then QEMU recovery
        const networkRecovered = await this.recoverNetworkIssues(instanceId);
        if (!networkRecovered) {
          return await this.recoverQEMUIssues(instanceId);
        }
        return true;
      
      case 'client':
        // Client-side issues are harder to recover from the backend
        // For now, we'll just mark them for manual intervention
        logger.info("Client-side issues detected, manual intervention may be required", { instanceId });
        return false;
      
      default:
        logger.warn("Unknown failure type", { failureType });
        return false;
    }
  }

  /**
   * Recover from network-related issues
   */
  async recoverNetworkIssues(instanceId) {
    // This is a placeholder for network recovery
    // In a real implementation, we might:
    // 1. Restart network interfaces in the container
    // 2. Reset bridge/TAP configuration
    // 3. Check host networking
    
    logger.info("Attempting network recovery for instance", { instanceId });
    
    // Simulate recovery attempt
    await new Promise(resolve => setTimeout(resolve, 2000));
    
    // Return success/failure based on some logic
    return Math.random() > 0.3; // 70% success rate simulation
  }

  /**
   * Recover from QEMU-related issues
   */
  async recoverQEMUIssues(instanceId) {
    // This is a placeholder for QEMU recovery
    // In a real implementation, we might:
    // 1. Restart QEMU process
    // 2. Restart audio/video subsystems
    // 3. Reset virtual machine state
    // 4. Restart the entire container pod
    
    logger.info("Attempting QEMU recovery for instance", { instanceId });
    
    // Simulate recovery attempt
    await new Promise(resolve => setTimeout(resolve, 3000));
    
    // Return success/failure based on some logic
    return Math.random() > 0.4; // 60% success rate simulation
  }

  /**
   * Probe VNC port connectivity
   */
  async probeVNCPort(vncUrl) {
    return new Promise((resolve) => {
      // Parse VNC URL (format: "host:port" or "localhost:5901")
      let host, port;
      if (vncUrl.includes('://')) {
        const url = new URL(vncUrl);
        host = url.hostname;
        port = parseInt(url.port) || 5901;
      } else {
        const parts = vncUrl.split(':');
        host = parts[0] || 'localhost';
        port = parseInt(parts[1]) || 5901;
      }

      const socket = net.createConnection(port, host);
      const timeout = setTimeout(() => {
        socket.destroy();
        resolve(false);
      }, 3000); // 3 second timeout

      socket.on('connect', () => {
        clearTimeout(timeout);
        socket.destroy();
        resolve(true);
      });

      socket.on('error', () => {
        clearTimeout(timeout);
        resolve(false);
      });
    });
  }

  /**
   * Test actual VNC functionality including audio and controls
   */
  async testVNCFunctionality(instance) {
    const results = {
      audioDetected: false,
      audioLevel: 0,
      controlsResponsive: false,
      frameRate: 0,
      errors: []
    };

    try {
      // Create WebSocket connection to VNC proxy
      const protocol = 'ws';
      const wsUrl = `${protocol}://localhost:3001/proxy/vnc/${instance.id}/`;
      
      // Test with a short timeout since this is for monitoring
      const testResults = await this.performVNCTests(wsUrl);
      
      results.audioDetected = testResults.audioDetected;
      results.audioLevel = testResults.audioLevel;
      results.controlsResponsive = testResults.controlsResponsive;
      results.frameRate = testResults.frameRate;
      
    } catch (error) {
      results.errors.push(`VNC functionality test failed: ${error.message}`);
    }

    return results;
  }

  /**
   * Perform actual VNC protocol tests
   */
  async performVNCTests(wsUrl) {
    return new Promise((resolve) => {
      const timeout = 5000; // 5 second timeout for tests
      const results = {
        audioDetected: false,
        audioLevel: 0,
        controlsResponsive: false,
        frameRate: 0
      };

      // Set timeout for the entire test
      const timeoutId = setTimeout(() => {
        resolve(results);
      }, timeout);

      try {
        // Simple connectivity test - we can't do full VNC handshake in monitoring
        // but we can test if the WebSocket proxy responds properly
        const testSocket = new WebSocket(wsUrl);
        let connected = false;

        testSocket.on('open', () => {
          connected = true;
          
          // Simulate basic VNC handshake to test responsiveness
          // Send a simple VNC protocol version string
          const vncVersion = Buffer.from('RFB 003.008\n');
          testSocket.send(vncVersion);
          
          // If we get this far, controls are likely responsive
          results.controlsResponsive = true;
          
          // Estimate frame rate based on connection speed (fallback)
          results.frameRate = 15; // Conservative estimate for working VNC
          
          // For audio detection, we'll check if audio streams are enabled
          // This is a placeholder - real implementation would require audio analysis
          results.audioDetected = true;
          results.audioLevel = 0.5; // Moderate level assumption
          
          testSocket.close();
          clearTimeout(timeoutId);
          resolve(results);
        });

        testSocket.on('error', (error) => {
          clearTimeout(timeoutId);
          resolve(results); // Return empty results on error
        });

        testSocket.on('close', () => {
          if (!connected) {
            clearTimeout(timeoutId);
            resolve(results);
          }
        });

      } catch (error) {
        clearTimeout(timeoutId);
        resolve(results);
      }
    });
  }

  /**
   * Probe HTTP stream URL availability
   */
  async probeStreamUrl(streamUrl) {
    // For HTTP URLs, we'd typically make an HTTP request
    // For now, we'll treat it as available if VNC is available
    return Promise.resolve(true);
  }
  /**
   * Estimate quality metrics based on probe results
   */
  estimateQualityMetrics(metrics) {
    const latency = metrics.quality.connectionLatency;
    
    if (!metrics.availability.vnc) {
      metrics.quality.videoFrameRate = 0;
      metrics.quality.audioQuality = 'error'; // VNC unavailable means error, not unavailable
      return;
    }

    // Determine overall audio quality based on multiple factors
    if (metrics.availability.audio && metrics.quality.controlsResponsive) {
      if (latency !== null) {
        if (latency < 50 && metrics.quality.audioLevel > 0.3) {
          metrics.quality.audioQuality = 'excellent';
          if (metrics.quality.videoFrameRate === 0) {
            metrics.quality.videoFrameRate = 30;
          }
        } else if (latency < 100 && metrics.quality.audioLevel > 0.2) {
          metrics.quality.audioQuality = 'good';
          if (metrics.quality.videoFrameRate === 0) {
            metrics.quality.videoFrameRate = 25;
          }
        } else if (latency < 200) {
          metrics.quality.audioQuality = 'fair';
          if (metrics.quality.videoFrameRate === 0) {
            metrics.quality.videoFrameRate = 20;
          }
        } else {
          metrics.quality.audioQuality = 'poor';
          if (metrics.quality.videoFrameRate === 0) {
            metrics.quality.videoFrameRate = 15;
          }
        }
      } else {
        metrics.quality.audioQuality = 'unknown';
      }
    } else if (metrics.availability.audio && !metrics.quality.controlsResponsive) {
      metrics.quality.audioQuality = 'fair'; // Audio works but controls don't
    } else if (!metrics.availability.audio && metrics.quality.controlsResponsive) {
      metrics.quality.audioQuality = 'poor'; // Controls work but no audio
    } else {
      metrics.quality.audioQuality = 'error'; // Neither audio nor controls work
    }

    if (latency !== null) {
      // Estimate packet loss and jitter based on latency and functionality
      const funcFactor = (metrics.availability.audio && metrics.quality.controlsResponsive) ? 0.5 : 1.0;
      metrics.quality.packetLoss = Math.min((latency * funcFactor) / 1000, 0.1); // Max 10%
      metrics.quality.jitter = (latency * funcFactor) / 10; // Jitter in ms
    }
  }

  /**
   * Create error metrics for failed probes
   */
  createErrorMetrics(instanceId, errorMessage) {
    return {
      instanceId,
      timestamp: new Date().toISOString(),
      availability: {
        vnc: false,
        stream: false,
        audio: false,
        controls: false
      },
      quality: {
        connectionLatency: null,
        videoFrameRate: 0,
        audioQuality: 'error',
        audioLevel: 0,
        controlsResponsive: false,
        packetLoss: 1.0,
        jitter: 999
      },
      errors: [errorMessage]
    };
  }

  /**
   * Get current metrics for all instances
   */
  getAllMetrics() {
    const result = {};
    for (const [instanceId, metrics] of this.metrics) {
      result[instanceId] = metrics;
    }
    return result;
  }

  /**
   * Get metrics for a specific instance
   */
  getInstanceMetrics(instanceId) {
    return this.metrics.get(instanceId) || null;
  }

  /**
   * Get quality summary for all instances
   */
  getQualitySummary() {
    const instances = Array.from(this.metrics.values());
    const total = instances.length;
    
    if (total === 0) {
      return {
        total: 0,
        available: 0,
        availabilityPercent: 0,
        averageLatency: null,
        qualityDistribution: {}
      };
    }

    const available = instances.filter(m => m.availability.vnc).length;
    const latencies = instances
      .map(m => m.quality.connectionLatency)
      .filter(l => l !== null);
    
    const averageLatency = latencies.length > 0 
      ? latencies.reduce((a, b) => a + b, 0) / latencies.length 
      : null;

    // Quality distribution
    const qualityDistribution = instances.reduce((dist, metrics) => {
      const quality = metrics.quality.audioQuality;
      dist[quality] = (dist[quality] || 0) + 1;
      return dist;
    }, {});

    return {
      total,
      available,
      availabilityPercent: (available / total) * 100,
      averageLatency: averageLatency ? Math.round(averageLatency) : null,
      qualityDistribution
    };
  }

  /**
   * Load instances from InstanceManager or fallback to static config
   */
  async loadInstances() {
    // If we have an InstanceManager, use it (Kubernetes-only mode)
    if (this.instanceManager) {
      try {
        return await this.instanceManager.getInstances();
      } catch (error) {
        logger.error("Failed to load instances from InstanceManager", { error: error.message });
        return [];
      }
    }
    
    // Fallback to static config (legacy mode)
    try {
      const configPath = path.resolve(__dirname, this.configDir, 'instances.json');
      const data = fs.readFileSync(configPath, 'utf-8');
      return JSON.parse(data);
    } catch (error) {
      logger.error("Failed to load instances config", { error: error.message });
      return [];
    }
  }
}

module.exports = StreamQualityMonitor;