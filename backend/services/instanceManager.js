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
      throw new Error('Kubernetes discovery not available and static configuration is disabled');
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
      
      // Don't throw here - let the server start but API calls will fail with meaningful errors
      console.warn('⚠️  Backend starting in degraded mode - API calls will fail until Kubernetes is available');
    }
  }

  async getInstances() {
    // Check if initialized first
    if (!this.initialized) {
      throw new Error('InstanceManager not initialized. Kubernetes discovery failed and static configuration is disabled.');
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
      
      if (discoveredInstances.length === 0) {
        throw new Error('No emulator instances discovered from Kubernetes cluster. Ensure pods are running with proper labels: app.kubernetes.io/component=emulator,app.kubernetes.io/part-of=lego-loco-cluster');
      }
      
      this.cachedInstances = discoveredInstances;
      this.lastDiscoveryTime = now;
      console.log(`✅ Auto-discovered ${discoveredInstances.length} instances from Kubernetes (static config disabled)`);
      return discoveredInstances;
    } catch (error) {
      console.error('❌ Kubernetes discovery failed:', error.message);
      throw new Error(`Kubernetes discovery failed: ${error.message}. Static configuration is disabled.`);
    }
  }

  async getInstanceById(instanceId) {
    const instances = await this.getInstances();
    return instances.find(instance => instance.id === instanceId);
  }

  async getKubernetesInfo() {
    if (!this.k8sDiscovery.isAvailable()) {
      return null;
    }

    try {
      const services = await this.k8sDiscovery.getServicesInfo();
      
      return {
        namespace: this.k8sDiscovery.getNamespace(),
        services: services,
        discoveryEnabled: true,
        lastDiscovery: this.lastDiscoveryTime,
        cachedInstancesCount: this.cachedInstances?.length || 0
      };
    } catch (error) {
      console.error('Failed to get Kubernetes info:', error.message);
      return {
        namespace: this.k8sDiscovery.getNamespace(),
        discoveryEnabled: true,
        error: error.message
      };
    }
  }

  startBackgroundDiscovery() {
    console.log('Starting background instance discovery...');
    
    // Initial discovery
    this.getInstances().catch(console.error);
    
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