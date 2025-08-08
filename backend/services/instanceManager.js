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
    this.staticInstances = null;
    
    // Start background discovery if Kubernetes is available
    if (this.k8sDiscovery.isAvailable()) {
      this.startBackgroundDiscovery();
    } else {
      console.log('Kubernetes discovery not available, using static configuration only');
    }
  }

  async getInstances() {
    // Try Kubernetes discovery first if available
    if (this.k8sDiscovery.isAvailable()) {
      const now = Date.now();
      
      // Use cached instances if recent
      if (this.cachedInstances && this.lastDiscoveryTime && 
          (now - this.lastDiscoveryTime) < this.discoveryInterval) {
        return this.cachedInstances;
      }
      
      try {
        const discoveredInstances = await this.k8sDiscovery.discoverEmulatorInstances();
        
        if (discoveredInstances.length > 0) {
          this.cachedInstances = discoveredInstances;
          this.lastDiscoveryTime = now;
          console.log(`Auto-discovered ${discoveredInstances.length} instances from Kubernetes`);
          return discoveredInstances;
        }
      } catch (error) {
        console.error('Kubernetes discovery failed:', error.message);
      }
    }

    // Fallback to static instances.json
    return this.getStaticInstances();
  }

  getStaticInstances() {
    if (this.staticInstances) {
      return this.staticInstances;
    }

    try {
      const instancesFile = path.join(this.configDir, 'instances.json');
      
      if (!fs.existsSync(instancesFile)) {
        console.warn('instances.json not found, returning empty array');
        return [];
      }
      
      let data = fs.readFileSync(instancesFile, 'utf-8');
      
      // Allow simple // comments in JSON files
      data = data.replace(/^\s*\/\/.*$/gm, "");
      
      this.staticInstances = JSON.parse(data);
      console.log(`Loaded ${this.staticInstances.length} instances from static configuration`);
      
      return this.staticInstances;
    } catch (error) {
      console.error('Failed to load static instances:', error.message);
      return [];
    }
  }

  async getProvisionedInstances() {
    const allInstances = await this.getInstances();
    
    // For Kubernetes-discovered instances, filter by ready status
    if (this.k8sDiscovery.isAvailable() && this.cachedInstances) {
      return allInstances.filter(instance => instance.ready);
    }
    
    // For static instances, apply existing logic
    try {
      const statusData = this.loadConfig('status');
      
      return allInstances
        .map(instance => ({
          ...instance,
          status: statusData[instance.id] || 'unknown',
          provisioned: statusData[instance.id] === 'ready' || statusData[instance.id] === 'running',
          ready: statusData[instance.id] === 'ready'
        }))
        .filter(instance => instance.provisioned);
    } catch (error) {
      console.error('Failed to load status data for static instances:', error.message);
      return allInstances.filter(instance => instance.provisioned !== false);
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

  loadConfig(name) {
    const file = path.join(this.configDir, `${name}.json`);
    
    if (!fs.existsSync(file)) {
      throw new Error(`Config file not found: ${file}`);
    }
    
    let data = fs.readFileSync(file, "utf-8");
    data = data.replace(/^\s*\/\/.*$/gm, "");
    return JSON.parse(data);
  }

  isUsingKubernetesDiscovery() {
    return this.k8sDiscovery.isAvailable() && this.cachedInstances !== null;
  }

  invalidateCache() {
    this.cachedInstances = null;
    this.lastDiscoveryTime = null;
    this.staticInstances = null;
  }

  async refreshDiscovery() {
    this.invalidateCache();
    return await this.getInstances();
  }
}

module.exports = InstanceManager;