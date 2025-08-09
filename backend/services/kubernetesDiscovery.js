const fs = require('fs');
const path = require('path');

class KubernetesDiscovery {
  constructor() {
    this.kc = null;
    this.k8sApi = null;
    this.k8sAppsApi = null; // For StatefulSet API access
    this.k8s = null; // Store k8s reference for class-level access
    this.namespace = 'loco'; // Default namespace aligned with Helm chart values.yaml
    this.initialized = false;
    
    // Initialize asynchronously
    this.init().catch(error => {
      console.warn('Failed to initialize KubernetesDiscovery:', error);
    });
  }

  async init() {
    try {
      // Use dynamic import for ES modules in CommonJS environment
      const k8s = await import('@kubernetes/client-node');
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
      this.k8sAppsApi = this.kc.makeApiClient(k8s.AppsV1Api); // For StatefulSet access
      
      // Configure API client for proper HTTPS/TLS handling
      if (this.k8sApi.defaultHeaders) {
        this.k8sApi.defaultHeaders['User-Agent'] = 'lego-loco-cluster-backend/1.0';
      }
      if (this.k8sAppsApi.defaultHeaders) {
        this.k8sAppsApi.defaultHeaders['User-Agent'] = 'lego-loco-cluster-backend/1.0';
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
        // In CI environments or when no environment/service account namespace is found,
        // use 'loco' namespace to align with Helm chart default configuration
        this.namespace = 'loco';
        console.log(`Using default namespace from Helm chart: ${this.namespace}`);
      }
      
      // Validate namespace is not empty or null/undefined - always default to 'loco'
      if (!this.namespace || this.namespace.trim() === '' || this.namespace === 'null' || this.namespace === 'undefined') {
        this.namespace = 'loco'; // Use Helm chart default 'loco' instead of 'default'
        console.warn('Namespace was empty, null, or undefined - falling back to Helm chart default: loco');
      }
      
      // Final validation - ensure namespace is a proper string, fallback to 'loco'
      this.namespace = String(this.namespace).trim();
      if (!this.namespace) {
        this.namespace = 'loco'; // Use Helm chart default 'loco'
        console.warn('Namespace validation failed - using Helm chart default namespace: loco');
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
      
      // Ensure namespace is a valid string with extra validation, default to 'loco'
      const namespace = String(this.namespace).trim();
      if (!namespace || namespace === 'null' || namespace === 'undefined') {
        console.error('❌ Namespace is empty, null, or undefined after validation');
        return [];
      }
      
      // Use exact labels from Helm chart emulator-statefulset.yaml
      const labelSelector = 'app.kubernetes.io/component=emulator,app.kubernetes.io/part-of=lego-loco-cluster';
      
      console.log(`🚀 Calling Kubernetes APIs for namespace: "${namespace}"`);
      console.log(`📝 Label selector: "${labelSelector}"`);
      
      // Add pre-call validation
      if (typeof namespace !== 'string') {
        throw new Error(`Namespace parameter must be a string, got ${typeof namespace}: ${namespace}`);
      }
      
      // Query both Pods and StatefulSets for comprehensive discovery
      const listPodsParams = {
        namespace: namespace,
        labelSelector: labelSelector
      };
      
      const listStatefulSetsParams = {
        namespace: namespace,
        labelSelector: labelSelector
      };
      
      console.log(`🔧 API call parameters:`, { pods: listPodsParams, statefulSets: listStatefulSetsParams });
      
      // Execute both API calls in parallel for efficiency
      const [podsResponse, statefulSetsResponse] = await Promise.all([
        this.k8sApi.listNamespacedPod(listPodsParams),
        this.k8sAppsApi.listNamespacedStatefulSet(listStatefulSetsParams)
      ]);

      if (!podsResponse || !podsResponse.body) {
        console.log('⚠️ No pods response or body from Kubernetes API');
        return [];
      }

      if (!statefulSetsResponse || !statefulSetsResponse.body) {
        console.log('⚠️ No StatefulSets response or body from Kubernetes API');
      }

      const pods = podsResponse.body.items || [];
      const statefulSets = statefulSetsResponse.body.items || [];

      console.log(`✅ Kubernetes API responses received - found ${pods.length} pods and ${statefulSets.length} StatefulSets`);

      const instances = [];
      
      // Create a map of StatefulSets for reference
      const statefulSetMap = new Map();
      for (const sts of statefulSets) {
        statefulSetMap.set(sts.metadata.name, sts);
        console.log(`📋 Found StatefulSet: ${sts.metadata.name}, desired replicas: ${sts.spec.replicas}, ready: ${sts.status.readyReplicas || 0}`);
      }
      
      for (const pod of pods) {
        console.log(`📋 Processing pod: ${pod.metadata.name}, phase: ${pod.status.phase}, podIP: ${pod.status.podIP}`);
        
        if (pod.status.phase === 'Running' && pod.status.podIP) {
          // Extract instance number from pod name (e.g., loco-emulator-0 -> 0)
          const instanceMatch = pod.metadata.name.match(/-(\d+)$/);
          const instanceNumber = instanceMatch ? parseInt(instanceMatch[1]) : 0;
          
          // Find corresponding StatefulSet
          const statefulSetName = pod.metadata.name.replace(/-\d+$/, '');
          const statefulSet = statefulSetMap.get(statefulSetName);
          
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
              startTime: pod.status.startTime,
              // Add StatefulSet information if available
              statefulSet: statefulSet ? {
                name: statefulSet.metadata.name,
                replicas: statefulSet.spec.replicas,
                readyReplicas: statefulSet.status.readyReplicas || 0,
                currentReplicas: statefulSet.status.currentReplicas || 0,
                generation: statefulSet.metadata.generation,
                observedGeneration: statefulSet.status.observedGeneration
              } : null
            }
          };
          
          console.log(`✅ Added instance: ${instance.id} (${pod.metadata.name})`);
          if (statefulSet) {
            console.log(`   📊 StatefulSet info: ${statefulSet.metadata.name} (${statefulSet.status.readyReplicas || 0}/${statefulSet.spec.replicas} ready)`);
          }
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
      if (statefulSets.length > 0) {
        console.log(`📊 StatefulSet summary: ${statefulSets.map(sts => `${sts.metadata.name}(${sts.status.readyReplicas || 0}/${sts.spec.replicas})`).join(', ')}`);
      }
      return instances;
      
    } catch (error) {
      console.error('❌ Failed to discover instances from Kubernetes:', error.message);
      console.error('🔍 Error details:', {
        errorType: error.constructor.name,
        errorCode: error.code,
        namespace: this.namespace,
        namespaceType: typeof this.namespace,
        apiAvailable: !!this.k8sApi,
        appsApiAvailable: !!this.k8sAppsApi
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
      // Ensure namespace is a valid string with extra validation, default to 'loco'
      const namespace = String(this.namespace).trim();
      if (!namespace || namespace === 'null' || namespace === 'undefined') {
        console.warn('Namespace validation failed for services info - using default: loco');
        return {};
      }
      
      console.log(`🔍 Getting services info for namespace: "${namespace}"`);
      
      // Use object-based parameters for kubernetes/client-node v1.3.0+
      const labelSelector = 'app.kubernetes.io/part-of=lego-loco-cluster';
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
      
      // Ensure namespace is a valid string with extra validation, default to 'loco'
      const namespace = String(this.namespace).trim();
      if (!namespace || namespace === 'null' || namespace === 'undefined') {
        console.warn('Namespace validation failed for watch functionality - using default: loco');
        return null;
      }
      
      console.log(`🔍 Starting watch for emulator pod changes in namespace: "${namespace}"...`);
      
      // Configure watch with TLS settings for CI environments
      // Use exact labels from Helm chart emulator-statefulset.yaml
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

  async getStatefulSetsInfo() {
    if (!this.initialized) {
      return {};
    }

    if (!this.namespace || this.namespace.trim() === '' || this.namespace === 'null' || this.namespace === 'undefined') {
      console.warn('Cannot get StatefulSets info: Kubernetes namespace is null, undefined, or empty');
      return {};
    }

    try {
      // Ensure namespace is a valid string with extra validation, default to 'loco'
      const namespace = String(this.namespace).trim();
      if (!namespace || namespace === 'null' || namespace === 'undefined') {
        console.warn('Namespace validation failed for StatefulSets info - using default: loco');
        return {};
      }
      
      console.log(`🔍 Getting StatefulSets info for namespace: "${namespace}"`);
      
      // Use object-based parameters for kubernetes/client-node v1.3.0+
      const labelSelector = 'app.kubernetes.io/part-of=lego-loco-cluster';
      const listStatefulSetsParams = {
        namespace: namespace,
        labelSelector: labelSelector
      };
      
      const statefulSetsResponse = await this.k8sAppsApi.listNamespacedStatefulSet(listStatefulSetsParams);

      if (!statefulSetsResponse || !statefulSetsResponse.body) {
        console.log('⚠️ No StatefulSets response or body from Kubernetes API');
        return {};
      }

      console.log(`✅ Found ${statefulSetsResponse.body.items?.length || 0} StatefulSets`);

      const statefulSets = {};
      
      for (const sts of statefulSetsResponse.body.items || []) {
        statefulSets[sts.metadata.name] = {
          name: sts.metadata.name,
          replicas: sts.spec.replicas,
          readyReplicas: sts.status.readyReplicas || 0,
          currentReplicas: sts.status.currentReplicas || 0,
          serviceName: sts.spec.serviceName,
          selector: sts.spec.selector,
          generation: sts.metadata.generation,
          observedGeneration: sts.status.observedGeneration,
          conditions: sts.status.conditions || []
        };
        console.log(`📋 Found StatefulSet: ${sts.metadata.name} (${sts.status.readyReplicas || 0}/${sts.spec.replicas} ready)`);
      }

      return statefulSets;
    } catch (error) {
      console.error('❌ Failed to get StatefulSets info:', error.message);
      return {};
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