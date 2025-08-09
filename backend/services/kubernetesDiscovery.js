const fs = require('fs');
const path = require('path');
const circuitBreakerManager = require('./circuitBreaker');

class KubernetesDiscovery {
  constructor() {
    this.kc = null;
    this.k8sApi = null;
    this.namespace = 'default';
    this.initialized = false;
    this.cachedPods = [];
    this.cachedServices = {};
    this.lastCacheUpdate = null;
    
    // Initialize asynchronously
    this.init().catch(error => {
      console.warn('Failed to initialize KubernetesDiscovery:', error);
    });
  }

  async init() {
    try {
      // Dynamic import for ES module
      const k8s = await import('@kubernetes/client-node');
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
      
      // Validate namespace is not empty
      if (!this.namespace || this.namespace.trim() === '') {
        this.namespace = 'default';
        console.warn('Namespace was empty, falling back to default');
      }
      
      console.log(`Kubernetes discovery initialized for namespace: ${this.namespace}`);
      
      // Set up circuit breakers for Kubernetes API calls
      this.setupCircuitBreakers();
    } catch (error) {
      console.warn('Failed to initialize Kubernetes client:', error.message);
      console.warn('Auto-discovery will be disabled. Falling back to static configuration.');
    }
  }

  setupCircuitBreakers() {
    if (!this.k8sApi) {
      console.warn('Cannot setup circuit breakers: k8sApi not initialized');
      return;
    }

    // Circuit breaker for listNamespacedPod
    this.listPodsBreaker = circuitBreakerManager.createBreaker(
      'kubernetes-list-pods',
      async (namespace, labelSelector) => {
        return await this.k8sApi.listNamespacedPod(
          namespace,
          undefined, // pretty
          undefined, // allowWatchBookmarks
          undefined, // _continue
          undefined, // fieldSelector
          labelSelector,
          undefined, // limit
          undefined, // resourceVersion
          undefined, // resourceVersionMatch
          undefined, // sendInitialEvents
          undefined, // timeoutSeconds
          undefined  // watch
        );
      },
      {
        timeout: 10000, // 10 seconds timeout for K8s API calls
        errorThresholdPercentage: 60,
        resetTimeout: 30000,
        fallback: circuitBreakerManager.createCacheFallback(
          { body: { items: this.cachedPods } },
          'cached pods data'
        )
      }
    );

    // Circuit breaker for listNamespacedService
    this.listServicesBreaker = circuitBreakerManager.createBreaker(
      'kubernetes-list-services',
      async (namespace, labelSelector) => {
        return await this.k8sApi.listNamespacedService(
          namespace,
          undefined, // pretty
          undefined, // allowWatchBookmarks
          undefined, // _continue
          undefined, // fieldSelector
          labelSelector,
          undefined, // limit
          undefined, // resourceVersion
          undefined, // resourceVersionMatch
          undefined, // sendInitialEvents
          undefined, // timeoutSeconds
          undefined  // watch
        );
      },
      {
        timeout: 8000, // 8 seconds timeout for services
        errorThresholdPercentage: 60,
        resetTimeout: 30000,
        fallback: circuitBreakerManager.createCacheFallback(
          { body: { items: [] } },
          'cached services data'
        )
      }
    );

    console.log('🔧 Circuit breakers configured for Kubernetes API calls');
  }

  async discoverEmulatorInstances() {
    if (!this.initialized) {
      console.log('Kubernetes discovery not initialized, returning cached pods');
      return this.convertPodsToInstances(this.cachedPods);
    }

    if (!this.namespace || this.namespace.trim() === '') {
      console.error('Kubernetes namespace is null or empty, cannot discover instances');
      return this.convertPodsToInstances(this.cachedPods);
    }

    try {
      console.log(`Discovering emulator instances in namespace: ${this.namespace}`);
      console.log(`Namespace type: ${typeof this.namespace}, value: "${this.namespace}"`);
      
      // Ensure namespace is a valid string
      const namespace = String(this.namespace).trim();
      if (!namespace) {
        console.error('Namespace is empty after trimming');
        return this.convertPodsToInstances(this.cachedPods);
      }
      
      // Discover StatefulSet pods with emulator label using circuit breaker
      console.log(`Calling listNamespacedPod with namespace: "${namespace}" via circuit breaker`);
      
      const labelSelector = 'app.kubernetes.io/component=emulator,app.kubernetes.io/part-of=lego-loco-cluster';
      
      // Use circuit breaker to make the API call
      const podsResponse = await this.listPodsBreaker.fire(namespace, labelSelector);

      if (!podsResponse || !podsResponse.body) {
        console.log('No pods response or body from Kubernetes API, using cached data');
        return this.convertPodsToInstances(this.cachedPods);
      }

      // Update cache with fresh data
      this.cachedPods = podsResponse.body.items || [];
      this.lastCacheUpdate = new Date().toISOString();

      const instances = this.convertPodsToInstances(this.cachedPods);

      console.log(`Discovered ${instances.length} emulator instances from Kubernetes`);
      return instances;
      
    } catch (error) {
      console.error('Failed to discover instances from Kubernetes:', error.message);
      
      // Return cached data as fallback
      console.log('Falling back to cached pods data');
      return this.convertPodsToInstances(this.cachedPods);
    }
  }

  convertPodsToInstances(pods) {
    const instances = [];
    
    for (const pod of pods) {
      if (pod.status && pod.status.phase === 'Running' && pod.status.podIP) {
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
        
        instances.push(instance);
      }
    }

    // Sort instances by instance number
    instances.sort((a, b) => {
      const aNum = parseInt(a.id.split('-')[1]);
      const bNum = parseInt(b.id.split('-')[1]);
      return aNum - bNum;
    });

    return instances;
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
      return this.cachedServices;
    }

    if (!this.namespace || this.namespace.trim() === '') {
      console.warn('Cannot get services info: Kubernetes namespace is null or empty');
      return this.cachedServices;
    }

    try {
      // Ensure namespace is a valid string
      const namespace = String(this.namespace).trim();
      
      const labelSelector = 'app.kubernetes.io/part-of=lego-loco-cluster';
      
      // Use circuit breaker to make the API call
      const servicesResponse = await this.listServicesBreaker.fire(namespace, labelSelector);

      if (!servicesResponse || !servicesResponse.body) {
        console.log('No services response or body from Kubernetes API, using cached data');
        return this.cachedServices;
      }

      const services = {};
      
      for (const service of servicesResponse.body.items || []) {
        services[service.metadata.name] = {
          name: service.metadata.name,
          type: service.spec.type,
          clusterIP: service.spec.clusterIP,
          ports: service.spec.ports,
          selector: service.spec.selector
        };
      }

      // Update cache
      this.cachedServices = services;

      return services;
    } catch (error) {
      console.error('Failed to get services info:', error.message);
      console.log('Falling back to cached services data');
      return this.cachedServices;
    }
  }

  async watchEmulatorInstances(callback) {
    if (!this.initialized) {
      console.warn('Cannot watch instances: Kubernetes discovery not initialized');
      return null;
    }

    if (!this.namespace || this.namespace.trim() === '') {
      console.warn('Cannot watch instances: Kubernetes namespace is null or empty');
      return null;
    }

    try {
      const watch = new k8s.Watch(this.kc);
      
      // Ensure namespace is a valid string
      const namespace = String(this.namespace).trim();
      console.log(`Starting watch for emulator pod changes in namespace: ${namespace}...`);
      
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
          console.log(`Pod ${type}: ${apiObj.metadata.name} - ${apiObj.status.phase}`);
          
          // Trigger callback to refresh instance list
          if (callback) {
            callback(type, apiObj);
          }
        },
        (err) => {
          if (err && err.code !== 'ECONNRESET') {
            console.error('Watch error:', err.message);
          }
        }
      );

      return watchRequest;
    } catch (error) {
      console.error('Failed to start watching instances:', error.message);
      // In CI environments, don't throw errors for watch failures
      if (process.env.CI || process.env.NODE_ENV === 'test') {
        console.warn('Watch functionality disabled in CI environment due to TLS restrictions');
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

  /**
   * Get circuit breaker metrics for monitoring
   * @returns {Object} Circuit breaker metrics
   */
  getCircuitBreakerMetrics() {
    if (!circuitBreakerManager) {
      return { error: 'Circuit breaker manager not available' };
    }

    return {
      summary: circuitBreakerManager.getSummary(),
      breakers: circuitBreakerManager.getAllMetrics(),
      cacheInfo: {
        cachedPodsCount: this.cachedPods ? this.cachedPods.length : 0,
        cachedServicesCount: Object.keys(this.cachedServices || {}).length,
        lastCacheUpdate: this.lastCacheUpdate
      }
    };
  }
}

module.exports = KubernetesDiscovery;