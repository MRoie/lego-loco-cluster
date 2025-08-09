const fs = require('fs');
const path = require('path');
const KubernetesDiscovery = require('./kubernetesDiscovery');

class InstanceManager {
  constructor(configDir) {
    this.configDir = configDir;
    this.k8sDiscovery = new KubernetesDiscovery();
    this.cachedInstances = null;
    this.lastDiscoveryTime = null;
    this.discoveryInterval = 30000; // 30 seconds
    this.initialized = false;
    
    // Initialize async
    this.initializeAsync();
  }

  async initializeAsync() {
    if (!this.k8sDiscovery.isAvailable()) {
      console.error('❌ Kubernetes discovery not available. Static configuration is disabled. Backend requires Kubernetes environment.');
      
      // Set initialized to true in test/CI environments to allow e2e tests with empty instance list
      if (process.env.NODE_ENV === 'test' || process.env.CI || process.env.ALLOW_EMPTY_DISCOVERY === 'true') {
        console.warn('⚠️  Test/CI environment detected - initializing with empty instances for e2e testing');
        this.initialized = true;
        this.cachedInstances = [];
        return; // Don't throw error in test environments
      } else {
        throw new Error('Kubernetes discovery not available and static configuration is disabled');
      }
    }

    // Test actual connectivity by trying to discover instances
    try {
      console.log('🔍 Testing Kubernetes connectivity...');
      await this.k8sDiscovery.discoverEmulatorInstances();
      console.log('✅ Kubernetes connectivity confirmed - static configuration disabled');
      this.startBackgroundDiscovery();
      this.initialized = true;
    } catch (error) {
      console.error('❌ Kubernetes connectivity test failed:', error.message);
      console.error('Static configuration is disabled. Backend requires active Kubernetes cluster.');
      
      // Set initialized to true in test/CI environments to allow e2e tests with empty instance list
      if (process.env.NODE_ENV === 'test' || process.env.CI || process.env.ALLOW_EMPTY_DISCOVERY === 'true') {
        console.warn('⚠️  Test/CI environment detected - initializing with empty instances for e2e testing');
        this.initialized = true;
        this.cachedInstances = [];
      } else {
        // Don't throw here - let the server start but API calls will fail with meaningful errors
        console.warn('⚠️  Backend starting in degraded mode - API calls will fail until Kubernetes is available');
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
      console.log('Test/CI environment: returning cached instances (may be empty for e2e tests)');
      return this.cachedInstances;
    }

    // ENFORCE Kubernetes-only discovery - NO static fallback
    if (!this.k8sDiscovery.isAvailable()) {
      throw new Error('Kubernetes discovery is not available. Static configuration fallback has been disabled. Please ensure the backend is running in a Kubernetes environment with proper RBAC permissions.');
    }

    const now = Date.now();
    
    // Use cached instances if recent
    if (this.cachedInstances && this.lastDiscoveryTime && 
        (now - this.lastDiscoveryTime) < this.discoveryInterval) {
      return this.cachedInstances;
    }
    
    try {
      const discoveredInstances = await this.k8sDiscovery.discoverEmulatorInstances();
      
      this.cachedInstances = discoveredInstances;
      this.lastDiscoveryTime = now;
      
      if (discoveredInstances.length === 0) {
        console.warn('⚠️ No emulator instances discovered from Kubernetes cluster. Ensure pods are running with proper labels: app.kubernetes.io/component=emulator,app.kubernetes.io/part-of=lego-loco-cluster');
      } else {
        console.log(`✅ Auto-discovered ${discoveredInstances.length} instances from Kubernetes (static config disabled)`);
      }
      
      return discoveredInstances;
    } catch (error) {
      console.error('❌ Kubernetes discovery failed:', error.message);
      
      // In CI/test environments, return empty array instead of throwing
      if (process.env.NODE_ENV === 'test' || process.env.CI || process.env.ALLOW_EMPTY_DISCOVERY === 'true') {
        console.warn('⚠️  CI/test environment: returning empty instances list due to discovery failure');
        this.cachedInstances = [];
        this.lastDiscoveryTime = now;
        return [];
      }
      
      throw new Error(`Kubernetes discovery failed: ${error.message}. Static configuration is disabled.`);
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
      console.error('Failed to get Kubernetes info:', error.message);
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
    console.log('Starting background instance discovery...');
    
    // Initial discovery - only if properly initialized
    if (this.initialized) {
      this.getInstances().catch(console.error);
    }
    
    // Set up periodic discovery
    this.discoveryTimer = setInterval(async () => {
      try {
        await this.k8sDiscovery.discoverEmulatorInstances();
      } catch (error) {
        console.error('Background discovery error:', error.message);
      }
    }, this.discoveryInterval);

    // Set up watch for real-time updates
    this.watchHandle = this.k8sDiscovery.watchEmulatorInstances((type, pod) => {
      console.log(`Instance ${type}: ${pod.metadata.name}`);
      // Invalidate cache to force refresh on next request
      this.cachedInstances = null;
      this.lastDiscoveryTime = null;
    });
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
        console.warn('Failed to stop watch handle:', error.message);
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