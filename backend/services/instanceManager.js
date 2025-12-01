const fs = require('fs');
const path = require('path');
const logger = require('../utils/logger');
const KubernetesDiscovery = require('./kubernetesDiscovery');
const EndpointsDiscovery = require('./endpointsDiscovery');

class InstanceManager {
  constructor(configDir = '/app/config') {
    this.configDir = configDir;
    this.instances = [];
    this.initialized = false;
    this.discoveryMode = process.env.DISCOVERY_MODE || 'kubernetes-endpoints';
    this.serviceName = process.env.EMULATOR_SERVICE_NAME || 'loco-loco-emulator';

    logger.info('InstanceManager initializing', {
      configDir: this.configDir,
      discoveryMode: this.discoveryMode,
      serviceName: this.serviceName
    });

    // Initialize discovery service based on mode
    this.kubernetesDiscovery = new KubernetesDiscovery();
    this.discovery = null; // Will be set in initializeAsync
    this.cachedInstances = null;
    this.lastDiscoveryTime = null;
    this.discoveryInterval = 30000; // 30 seconds

    // Initialize async
    this.initializeAsync();
  }

  async initializeAsync() {
    // Wait for KubernetesDiscovery to initialize
    let retries = 0;
    const maxRetries = 10;

    while (!this.kubernetesDiscovery.isAvailable() && retries < maxRetries) {
      logger.info("Waiting for Kubernetes discovery to initialize", { attempt: retries + 1, maxRetries });
      await new Promise(resolve => setTimeout(resolve, 1000));
      retries++;
    }

    if (!this.kubernetesDiscovery.isAvailable()) {
      logger.error('Kubernetes discovery not available. Static configuration is disabled. Backend requires Kubernetes environment.');

      // Set initialized to true in test/CI environments
      if (process.env.NODE_ENV === 'test' || process.env.CI || process.env.ALLOW_EMPTY_DISCOVERY === 'true') {
        logger.warn("Test/CI environment detected - initializing with empty instances for e2e testing");
        this.initialized = true;
        this.cachedInstances = [];
        return;
      } else {
        throw new Error('Kubernetes discovery not available and static configuration is disabled');
      }
    }

    // Instantiate the appropriate discovery service based on mode
    logger.info('Initializing discovery service', { mode: this.discoveryMode });

    if (this.discoveryMode === 'kubernetes-endpoints') {
      // Use Endpoints-based discovery
      const k8sApi = this.kubernetesDiscovery.k8sApi;
      const kc = this.kubernetesDiscovery.kc;
      const k8s = this.kubernetesDiscovery.k8s;
      const namespace = this.kubernetesDiscovery.getNamespace();

      this.discovery = new EndpointsDiscovery(k8sApi, kc, k8s, namespace, this.serviceName);
      logger.info('Using Endpoints-based discovery', { serviceName: this.serviceName, namespace });
    } else {
      // Use Pod-based discovery (legacy)
      this.discovery = this.kubernetesDiscovery;
      logger.info('Using Pod-based discovery (legacy mode)');
    }

    // Test connectivity by trying to discover instances
    try {
      logger.info("Testing discovery connectivity...");
      const instances = await this.discovery.discoverInstances();
      logger.info("Discovery connectivity confirmed", {
        mode: this.discoveryMode,
        instanceCount: instances.length
      });
      this.startBackgroundDiscovery();
      this.initialized = true;
    } catch (error) {
      logger.error("Discovery connectivity test failed", { error: error.message });
      logger.error("Static configuration is disabled. Backend requires active Kubernetes cluster.");

      // Set initialized to true in test/CI environments
      if (process.env.NODE_ENV === 'test' || process.env.CI || process.env.ALLOW_EMPTY_DISCOVERY === 'true') {
        logger.warn("Test/CI environment detected - initializing with empty instances for e2e testing");
        this.initialized = true;
        this.cachedInstances = [];
      } else {
        logger.warn("Backend starting in degraded mode - API calls will fail until Kubernetes is available");
      }
    }
  }

  async getInstances() {
    // Check if initialized first
    if (!this.initialized) {
      throw new Error('InstanceManager not initialized. Kubernetes discovery failed and static configuration is disabled.');
    }

    // In test/CI environments, return cached empty instances if no K8s available
    if ((process.env.NODE_ENV === 'test' || process.env.CI || process.env.ALLOW_EMPTY_DISCOVERY === 'true') && this.cachedInstances !== null) {
      logger.info("Test/CI environment: returning cached instances (may be empty for e2e tests)");
      return this.cachedInstances;
    }

    // ENFORCE Kubernetes-only discovery - NO static fallback
    if (!this.kubernetesDiscovery.isAvailable() || !this.discovery) {
      throw new Error('Kubernetes discovery is not available. Static configuration fallback has been disabled. Please ensure the backend is running in a Kubernetes environment with proper RBAC permissions.');
    }

    const now = Date.now();

    // Use cached instances if recent
    if (this.cachedInstances && this.lastDiscoveryTime &&
      (now - this.lastDiscoveryTime) < this.discoveryInterval) {
      logger.debug("Returning cached instances", {
        age: now - this.lastDiscoveryTime,
        count: this.cachedInstances.length
      });
      return this.cachedInstances;
    }

    // Discover fresh instances using the configured discovery service
    try {
      const instances = await this.discovery.discoverInstances();
      this.cachedInstances = instances;
      this.lastDiscoveryTime = now;
      return instances;
    } catch (error) {
      logger.error('Failed to discover instances', { error: error.message });
      // Return cached instances if available, otherwise empty array
      return this.cachedInstances || [];
    }
  }

  async getInstanceById(instanceId) {
    const instances = await this.getInstances();
    return instances.find(instance => instance.id === instanceId);
  }

  async getKubernetesInfo() {
    if (!this.k8sDiscovery.isAvailable()) {
      return {
        namespace: 'default',
        services: {},
        discoveryEnabled: false,
        error: 'Kubernetes client not available',
        lastDiscovery: null,
        cachedInstancesCount: 0
      };
    }

    try {
      const services = await this.k8sDiscovery.getServicesInfo();

      return {
        namespace: this.k8sDiscovery.getNamespace(),
        services: services,
        discoveryEnabled: true,
        lastDiscovery: this.lastDiscoveryTime,
        cachedInstancesCount: this.cachedInstances?.length || 0,
        kubernetes: {
          available: true,
          namespace: this.k8sDiscovery.getNamespace(),
          servicesFound: Object.keys(services).length
        }
      };
    } catch (error) {
      logger.error("Failed to get Kubernetes info", { error: error.message });
      return {
        namespace: this.k8sDiscovery.getNamespace(),
        services: {},
        discoveryEnabled: true,
        error: error.message,
        lastDiscovery: this.lastDiscoveryTime,
        cachedInstancesCount: this.cachedInstances?.length || 0,
        kubernetes: {
          available: true,
          namespace: this.k8sDiscovery.getNamespace(),
          error: error.message
        }
      };
    }
  }

  startBackgroundDiscovery() {
    logger.info("Starting background instance discovery...", { mode: this.discoveryMode });

    // Set up periodic discovery
    this.discoveryTimer = setInterval(async () => {
      try {
        await this.discovery.discoverInstances();
      } catch (error) {
        logger.error("Background discovery error", { error: error.message });
      }
    }, this.discoveryInterval);

    // Set up watch for real-time updates (if using Endpoints discovery)
    if (this.discoveryMode === 'kubernetes-endpoints' && this.discovery.watchEndpoints) {
      this.watchHandle = this.discovery.watchEndpoints((type, endpoint) => {
        logger.debug("Endpoints changed", { type, service: this.serviceName });
        // Invalidate cache to force refresh on next request
        this.cachedInstances = null;
        this.lastDiscoveryTime = null;
      });
    } else if (this.kubernetesDiscovery.watchEmulatorInstances) {
      // Fallback to pod watch for legacy mode
      this.watchHandle = this.kubernetesDiscovery.watchEmulatorInstances((type, pod) => {
        logger.debug("Instance discovered", { type, podName: pod.metadata.name });
        // Invalidate cache to force refresh on next request
        this.cachedInstances = null;
        this.lastDiscoveryTime = null;
      });
    }
  }

  stopBackgroundDiscovery() {
    if (this.discoveryTimer) {
      clearInterval(this.discoveryTimer);
      this.discoveryTimer = null;
    }

    if (this.watchHandle) {
      try {
        this.watchHandle.abort();
      } catch (error) {
        logger.warn("Failed to stop watch handle", { error: error.message });
      }
      this.watchHandle = null;
    }
  }

  isUsingKubernetesDiscovery() {
    return this.k8sDiscovery.isAvailable();
  }

  invalidateCache() {
    this.cachedInstances = null;
    this.lastDiscoveryTime = null;
  }

  async refreshDiscovery() {
    this.invalidateCache();
    return await this.getInstances();
  }
}

module.exports = InstanceManager;