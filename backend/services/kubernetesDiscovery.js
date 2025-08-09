const fs = require('fs');
const path = require('path');

class KubernetesDiscovery {
  constructor() {
    this.kc = null;
    this.k8sApi = null;
    this.k8s = null; // Store k8s reference for class-level access
    this.namespace = 'default';
    this.initialized = false;
    
    // Initialize asynchronously
    this.init().catch(error => {
      console.warn('Failed to initialize KubernetesDiscovery:', error);
    });
  }

  async init() {
    try {
      // Use CommonJS require instead of dynamic import since this is a CommonJS module
      const k8s = require('@kubernetes/client-node');
      this.k8s = k8s; // Store reference for later use
      this.kc = new k8s.KubeConfig();
      
      // Try to load in-cluster config first (when running in Kubernetes)
      if (fs.existsSync('/var/run/secrets/kubernetes.io/serviceaccount/token')) {
        this.kc.loadFromCluster();
        console.log('Loaded Kubernetes in-cluster configuration');
      } else {
        // Fallback to default kubeconfig
        this.kc.loadFromDefault();
        console.log('Loaded Kubernetes configuration from default kubeconfig');
      }
      
      this.k8sApi = this.kc.makeApiClient(k8s.CoreV1Api);
      
      // Configure API client for proper HTTPS/TLS handling
      if (this.k8sApi.defaultHeaders) {
        this.k8sApi.defaultHeaders['User-Agent'] = 'lego-loco-cluster-backend/1.0';
      }
      
      this.initialized = true;
      
      // Try to detect namespace from environment or service account
      if (process.env.KUBERNETES_NAMESPACE) {
        this.namespace = process.env.KUBERNETES_NAMESPACE;
        console.log(`Using namespace from KUBERNETES_NAMESPACE: ${this.namespace}`);
      } else if (fs.existsSync('/var/run/secrets/kubernetes.io/serviceaccount/namespace')) {
        this.namespace = fs.readFileSync('/var/run/secrets/kubernetes.io/serviceaccount/namespace', 'utf8').trim();
        console.log(`Using namespace from service account: ${this.namespace}`);
      } else {
        // In CI environments, use default namespace
        this.namespace = 'default';
        console.log(`Using default namespace: ${this.namespace}`);
      }
      
      // Validate namespace is not empty or null/undefined
      if (!this.namespace || this.namespace.trim() === '' || this.namespace === 'null' || this.namespace === 'undefined') {
        this.namespace = 'default';
        console.warn('Namespace was empty, null, or undefined - falling back to default');
      }
      
      // Final validation - ensure namespace is a proper string
      this.namespace = String(this.namespace).trim();
      if (!this.namespace) {
        this.namespace = 'default';
        console.warn('Namespace validation failed - using default namespace');
      }
      
      console.log(`Kubernetes discovery initialized for namespace: "${this.namespace}" (type: ${typeof this.namespace})`);
      console.log(`Namespace validation - length: ${this.namespace.length}, empty check: ${!this.namespace}`);
    } catch (error) {
      console.warn('Failed to initialize Kubernetes client:', error.message);
      console.warn('Auto-discovery will be disabled. Falling back to static configuration.');
    }
  }

  async discoverEmulatorInstances() {
    if (!this.initialized) {
      console.log('Kubernetes discovery not initialized, returning empty array');
      return [];
    }

    if (!this.namespace || this.namespace.trim() === '' || this.namespace === 'null' || this.namespace === 'undefined') {
      console.error('Kubernetes namespace is null, undefined, or empty, cannot discover instances');
      return [];
    }

    try {
      console.log(`🔍 Discovering emulator instances in namespace: "${this.namespace}"`);
      console.log(`📊 Debug info - Namespace type: ${typeof this.namespace}, value: "${this.namespace}", length: ${this.namespace.length}`);
      
      // Ensure namespace is a valid string with extra validation
      const namespace = String(this.namespace).trim();
      if (!namespace || namespace === 'null' || namespace === 'undefined') {
        console.error('❌ Namespace is empty, null, or undefined after validation');
        return [];
      }
      
      // Log detailed API call info
      console.log(`🚀 Calling Kubernetes API: listNamespacedPod(namespace="${namespace}")`);
      console.log(`📝 Label selector: "app.kubernetes.io/component=emulator,app.kubernetes.io/part-of=lego-loco-cluster"`);
      
      // Use positional parameters for maximum compatibility with different client-node versions
      const labelSelector = 'app.kubernetes.io/component=emulator,app.kubernetes.io/part-of=lego-loco-cluster';
      
      // Add pre-call validation
      if (typeof namespace !== 'string') {
        throw new Error(`Namespace parameter must be a string, got ${typeof namespace}: ${namespace}`);
      }
      
      // Use object-based parameters for kubernetes/client-node v1.3.0+
      const listPodsParams = {
        namespace: namespace,
        labelSelector: labelSelector
      };
      
      console.log(`🔧 API call parameters:`, listPodsParams);
      
      const podsResponse = await this.k8sApi.listNamespacedPod(listPodsParams);

      if (!podsResponse || !podsResponse.body) {
        console.log('⚠️ No pods response or body from Kubernetes API');
        return [];
      }

      console.log(`✅ Kubernetes API response received - found ${podsResponse.body.items?.length || 0} pods`);

      const instances = [];
      
      for (const pod of podsResponse.body.items || []) {
        console.log(`📋 Processing pod: ${pod.metadata.name}, phase: ${pod.status.phase}, podIP: ${pod.status.podIP}`);
        
        if (pod.status.phase === 'Running' && pod.status.podIP) {
          // Extract instance number from pod name (e.g., loco-emulator-0 -> 0)
          const instanceMatch = pod.metadata.name.match(/-(\d+)$/);
          const instanceNumber = instanceMatch ? parseInt(instanceMatch[1]) : 0;
          
          const instance = {
            id: `instance-${instanceNumber}`,
            name: `Windows 98 - ${instanceNumber === 0 ? 'Game Server' : `Client ${instanceNumber}`}`,
            description: instanceNumber === 0 ? 'Primary gaming instance with full Lego Loco installation' : 'Player client instance',
            podName: pod.metadata.name,
            podIP: pod.status.podIP,
            streamUrl: `http://localhost:${6080 + instanceNumber}/vnc${instanceNumber}`,
            vncUrl: `${pod.metadata.name}:5901`,
            healthUrl: `http://${pod.metadata.name}:8080`,
            provisioned: true,
            ready: pod.status.phase === 'Running',
            status: this.mapPodStatusToInstanceStatus(pod.status),
            discoveredAt: new Date().toISOString(),
            kubernetes: {
              namespace: pod.metadata.namespace,
              nodeName: pod.spec.nodeName,
              podIP: pod.status.podIP,
              startTime: pod.status.startTime
            }
          };
          
          console.log(`✅ Added instance: ${instance.id} (${pod.metadata.name})`);
          instances.push(instance);
        } else {
          console.log(`⏭️ Skipped pod ${pod.metadata.name}: phase=${pod.status.phase}, podIP=${pod.status.podIP}`);
        }
      }

      // Sort instances by instance number
      instances.sort((a, b) => {
        const aNum = parseInt(a.id.split('-')[1]);
        const bNum = parseInt(b.id.split('-')[1]);
        return aNum - bNum;
      });

      console.log(`🎯 Discovered ${instances.length} emulator instances from Kubernetes`);
      if (instances.length > 0) {
        console.log(`📋 Instance summary: ${instances.map(i => i.id).join(', ')}`);
      }
      return instances;
      
    } catch (error) {
      console.error('❌ Failed to discover instances from Kubernetes:', error.message);
      console.error('🔍 Error details:', {
        errorType: error.constructor.name,
        errorCode: error.code,
        namespace: this.namespace,
        namespaceType: typeof this.namespace,
        apiAvailable: !!this.k8sApi
      });
      return [];
    }
  }

  mapPodStatusToInstanceStatus(podStatus) {
    if (podStatus.phase === 'Running') {
      // Check if all containers are ready
      const allReady = podStatus.containerStatuses?.every(cs => cs.ready) ?? false;
      return allReady ? 'ready' : 'booting';
    } else if (podStatus.phase === 'Pending') {
      return 'booting';
    } else if (podStatus.phase === 'Failed') {
      return 'error';
    } else {
      return 'unknown';
    }
  }

  async getServicesInfo() {
    if (!this.initialized) {
      return {};
    }

    if (!this.namespace || this.namespace.trim() === '' || this.namespace === 'null' || this.namespace === 'undefined') {
      console.warn('Cannot get services info: Kubernetes namespace is null, undefined, or empty');
      return {};
    }

    try {
      // Ensure namespace is a valid string with extra validation
      const namespace = String(this.namespace).trim();
      if (!namespace || namespace === 'null' || namespace === 'undefined') {
        console.warn('Namespace validation failed for services info');
        return {};
      }
      
      console.log(`🔍 Getting services info for namespace: "${namespace}"`);
      
      // Use object-based parameters for kubernetes/client-node v1.3.0+
      const listServicesParams = {
        namespace: namespace,
        labelSelector: labelSelector
      };
      
      const servicesResponse = await this.k8sApi.listNamespacedService(listServicesParams);

      if (!servicesResponse || !servicesResponse.body) {
        console.log('⚠️ No services response or body from Kubernetes API');
        return {};
      }

      console.log(`✅ Found ${servicesResponse.body.items?.length || 0} services`);

      const services = {};
      
      for (const service of servicesResponse.body.items || []) {
        services[service.metadata.name] = {
          name: service.metadata.name,
          type: service.spec.type,
          clusterIP: service.spec.clusterIP,
          ports: service.spec.ports,
          selector: service.spec.selector
        };
        console.log(`📋 Found service: ${service.metadata.name} (${service.spec.type})`);
      }

      return services;
    } catch (error) {
      console.error('❌ Failed to get services info:', error.message);
      return {};
    }
  }

  async watchEmulatorInstances(callback) {
    if (!this.initialized) {
      console.warn('Cannot watch instances: Kubernetes discovery not initialized');
      return null;
    }

    if (!this.namespace || this.namespace.trim() === '' || this.namespace === 'null' || this.namespace === 'undefined') {
      console.warn('Cannot watch instances: Kubernetes namespace is null, undefined, or empty');
      return null;
    }

    try {
      // Use the stored k8s reference instead of undefined variable
      if (!this.k8s) {
        console.error('❌ Kubernetes client library not available for watch functionality');
        return null;
      }
      
      const watch = new this.k8s.Watch(this.kc);
      
      // Ensure namespace is a valid string with extra validation
      const namespace = String(this.namespace).trim();
      if (!namespace || namespace === 'null' || namespace === 'undefined') {
        console.warn('Namespace validation failed for watch functionality');
        return null;
      }
      
      console.log(`🔍 Starting watch for emulator pod changes in namespace: "${namespace}"...`);
      
      // Configure watch with TLS settings for CI environments
      const watchOptions = {
        labelSelector: 'app.kubernetes.io/component=emulator,app.kubernetes.io/part-of=lego-loco-cluster'
      };
      
      // Skip TLS verification in CI environments to avoid "HTTP protocol is not allowed" errors
      if (process.env.CI || process.env.NODE_ENV === 'test') {
        console.log('CI environment detected - configuring watch with relaxed TLS settings');
      }
      
      const watchRequest = await watch.watch(
        `/api/v1/namespaces/${namespace}/pods`,
        watchOptions,
        (type, apiObj) => {
          console.log(`📋 Pod ${type}: ${apiObj.metadata.name} - ${apiObj.status.phase}`);
          
          // Trigger callback to refresh instance list
          if (callback) {
            callback(type, apiObj);
          }
        },
        (err) => {
          if (err && err.code !== 'ECONNRESET') {
            console.error('❌ Watch error:', err.message);
          }
        }
      );

      console.log(`✅ Watch established for namespace: "${namespace}"`);
      return watchRequest;
    } catch (error) {
      console.error('❌ Failed to start watching instances:', error.message);
      // In CI environments, don't throw errors for watch failures
      if (process.env.CI || process.env.NODE_ENV === 'test') {
        console.warn('⚠️ Watch functionality disabled in CI environment due to TLS restrictions');
        return null;
      }
      // Don't throw error for watch failures, just return null
      return null;
    }
  }

  isAvailable() {
    return this.initialized;
  }

  getNamespace() {
    return this.namespace;
  }
}

module.exports = KubernetesDiscovery;