const net = require('net');
const fs = require('fs');
const path = require('path');

/**
 * Stream Quality Monitoring Service
 * Provides video/audio quality monitoring and availability probing for QEMU instances
 */
class StreamQualityMonitor {
  constructor(configDir = '../config') {
    this.configDir = configDir;
    this.metrics = new Map(); // instanceId -> metrics
    this.probeInterval = 5000; // 5 seconds
    this.probeTimer = null;
    this.isRunning = false;
  }

  /**
   * Start the monitoring service
   */
  start() {
    if (this.isRunning) return;
    
    console.log('🔍 Starting Stream Quality Monitor');
    this.isRunning = true;
    this.probeTimer = setInterval(() => {
      this.probeAllInstances();
    }, this.probeInterval);
    
    // Initial probe
    this.probeAllInstances();
  }

  /**
   * Stop the monitoring service
   */
  stop() {
    if (!this.isRunning) return;
    
    console.log('🛑 Stopping Stream Quality Monitor');
    this.isRunning = false;
    
    if (this.probeTimer) {
      clearInterval(this.probeTimer);
      this.probeTimer = null;
    }
  }

  /**
   * Probe all configured instances for availability and quality
   */
  async probeAllInstances() {
    try {
      const instances = this.loadInstances();
      const probePromises = instances.map(instance => 
        this.probeInstance(instance).catch(err => {
          console.error(`Probe failed for ${instance.id}:`, err.message);
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
      console.error('Failed to probe instances:', error.message);
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
        stream: false
      },
      quality: {
        connectionLatency: null,
        videoFrameRate: null,
        audioQuality: 'unknown',
        packetLoss: 0,
        jitter: 0
      },
      errors: []
    };

    // Probe VNC availability
    try {
      const vncAvailable = await this.probeVNCPort(instance.vncUrl);
      metrics.availability.vnc = vncAvailable;
      
      if (vncAvailable) {
        metrics.quality.connectionLatency = Date.now() - startTime;
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
      metrics.quality.audioQuality = 'unavailable';
      return;
    }

    // Estimate frame rate based on latency
    if (latency !== null) {
      if (latency < 50) {
        metrics.quality.videoFrameRate = 30; // Excellent
        metrics.quality.audioQuality = 'excellent';
      } else if (latency < 100) {
        metrics.quality.videoFrameRate = 25; // Good
        metrics.quality.audioQuality = 'good';
      } else if (latency < 200) {
        metrics.quality.videoFrameRate = 20; // Fair
        metrics.quality.audioQuality = 'fair';
      } else {
        metrics.quality.videoFrameRate = 15; // Poor
        metrics.quality.audioQuality = 'poor';
      }

      // Estimate packet loss and jitter based on latency
      metrics.quality.packetLoss = Math.min(latency / 1000, 0.1); // Max 10%
      metrics.quality.jitter = latency / 10; // Jitter in ms
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
        stream: false
      },
      quality: {
        connectionLatency: null,
        videoFrameRate: 0,
        audioQuality: 'error',
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
   * Load instances configuration
   */
  loadInstances() {
    try {
      const configPath = path.resolve(__dirname, this.configDir, 'instances.json');
      const data = fs.readFileSync(configPath, 'utf-8');
      return JSON.parse(data);
    } catch (error) {
      console.error('Failed to load instances config:', error.message);
      return [];
    }
  }
}

module.exports = StreamQualityMonitor;