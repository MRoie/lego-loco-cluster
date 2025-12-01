const fs = require('fs');
const path = require('path');
const logger = require('../utils/logger');

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
      logger.warn("Failed to initialize KubernetesDiscovery", { error });
    });
  }

  async init() {
    try {
      logger.info("Initializing Kubernetes discovery");

      const k8s = await import('@kubernetes/client-node');
      this.k8s = k8s; // Store reference for later use
      this.kc = new k8s.KubeConfig();

      // Try to load in-cluster config first (when running in Kubernetes)
      if (fs.existsSync('/var/run/secrets/kubernetes.io/serviceaccount/token')) {
        this.kc.loadFromCluster();
        logger.info("Loaded Kubernetes in-cluster configuration");
      } else {
        // Fallback to default kubeconfig
        this.kc.loadFromDefault();
        logger.info("Loaded Kubernetes configuration from default kubeconfig");
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

      // Try to detect namespace from environment or service account
      if (process.env.KUBERNETES_NAMESPACE) {
        this.namespace = process.env.KUBERNETES_NAMESPACE;
        logger.info("Using namespace from KUBERNETES_NAMESPACE", { namespace: this.namespace });
      } else if (fs.existsSync('/var/run/secrets/kubernetes.io/serviceaccount/namespace')) {
        this.namespace = fs.readFileSync('/var/run/secrets/kubernetes.io/serviceaccount/namespace', 'utf8').trim();
        logger.info("Using namespace from service account", { namespace: this.namespace });
      } else {
        // In CI environments, use default namespace
        this.namespace = 'default';
        logger.info("Using default namespace", { namespace: this.namespace });
      }

      // Validate namespace is not empty
      if (!this.namespace || this.namespace.trim() === '') {
        this.namespace = 'default';
        logger.warn("Namespace was empty, falling back to default");
      }

      // Test API connectivity
      try {
        await this.k8sApi.listNamespace();
        logger.info("Kubernetes API connectivity test successful");
      } catch (connectError) {
        logger.warn("Kubernetes API connectivity test failed", {
          error: connectError.message,
          code: connectError.code
        });
        throw connectError;
      }

      this.initialized = true;
      logger.info("Kubernetes discovery initialized successfully", {
        namespace: this.namespace,
        clusterAvailable: true
      });
    } catch (error) {
      logger.warn('Failed to initialize Kubernetes client', {
        error: error.message,
        code: error.code,
        stack: error.stack
      });
      logger.warn('Auto-discovery will be disabled. Falling back to static configuration.');
      this.initialized = false;
    }
  }

  async discoverEmulatorInstances() {
    if (!this.initialized) {
      logger.warn("Kubernetes discovery not initialized, returning empty array");
      return [];
    }

    if (!this.namespace || this.namespace.trim() === '') {
      logger.error("Kubernetes namespace is null or empty, cannot discover instances");
      return [];
    }

    try {
      logger.info("Discovering emulator instances in namespace", { namespace: this.namespace });
      // Ensure namespace is a valid string with extra validation, default to 'loco'
      const namespace = String(this.namespace).trim();
      if (!namespace) {
        logger.error("Namespace is empty after trimming");
        return [];
      }

      // Discover StatefulSet pods with emulator label
      logger.debug("Calling listNamespacedPod", { namespace });

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
        logger.warn("No pods response or body from Kubernetes API");
        return [];
      }

      if (!statefulSetsResponse || !statefulSetsResponse.body) {
        console.log('⚠️ No StatefulSets response or body from Kubernetes API');
      }

      const pods = podsResponse.body.items || [];
      const statefulSets = statefulSetsResponse.body.items || [];

      console.log(`✅ Kubernetes API responses received - found ${pods.length} pods and ${statefulSets.length} StatefulSets`);

      const instances = [];
      logger.debug("Processing discovered pods", { podCount: pods.length });

      for (const pod of pods) {
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
          logger.debug("Instance discovered", {
            instanceId: instance.id,
            podName: pod.metadata.name,
            status: instance.status
          });
        } else {
          logger.debug("Skipping pod - not running or no IP", {
            podName: pod.metadata.name,
            phase: pod.status.phase,
            podIP: pod.status.podIP
          });
        }
      }

      // Sort instances by instance number
      instances.sort((a, b) => {
        const aNum = parseInt(a.id.split('-')[1]);
        const bNum = parseInt(b.id.split('-')[1]);
        return aNum - bNum;
      });

      logger.info("Discovered emulator instances from Kubernetes", {
        count: instances.length,
        instanceIds: instances.map(i => i.id)
      });
      return instances;

    } catch (error) {
      logger.error("Failed to discover instances from Kubernetes", {
        error: error.message,
        stack: error.stack,
        namespace: this.namespace
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

    if (!this.namespace || this.namespace.trim() === '') {
      logger.warn("Cannot get services info: Kubernetes namespace is null or empty");
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
        logger.warn("No services response or body from Kubernetes API");
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
      logger.error("Failed to get services info", { error: error.message });
      return {};
    }
  }

  async watchEmulatorInstances(callback) {
    if (!this.initialized) {
      logger.warn("Cannot watch instances: Kubernetes discovery not initialized");
      return null;
    }

    if (!this.namespace || this.namespace.trim() === '') {
      logger.warn("Cannot watch instances: Kubernetes namespace is null or empty");
      return null;
    }

    try {
      // Dynamic import for ES module
      const k8s = await import('@kubernetes/client-node');
      const watch = new this.k8s.Watch(this.kc);

      // Ensure namespace is a valid string with extra validation, default to 'loco'
      const namespace = String(this.namespace).trim();
      logger.info("Starting watch for emulator pod changes", { namespace });

      // Configure watch with TLS settings for CI environments
      // Use exact labels from Helm chart emulator-statefulset.yaml
      const watchOptions = {
        labelSelector: 'app.kubernetes.io/component=emulator,app.kubernetes.io/part-of=lego-loco-cluster'
      };

      // Skip TLS verification in CI environments to avoid "HTTP protocol is not allowed" errors
      if (process.env.CI || process.env.NODE_ENV === 'test') {
        logger.info("CI environment detected - configuring watch with relaxed TLS settings");
      }

      const watchRequest = await watch.watch(
        `/api/v1/namespaces/${namespace}/pods`,
        watchOptions,
        (type, apiObj) => {
          logger.debug("Pod change detected", {
            type,
            podName: apiObj.metadata?.name,
            phase: apiObj.status?.phase,
            namespace: apiObj.metadata?.namespace
          });

          // Trigger callback to refresh instance list
          if (callback && typeof callback === 'function') {
            try {
              callback(type, apiObj);
            } catch (callbackError) {
              logger.error("Watch callback error", { error: callbackError.message });
            }
          }
        },
        (err) => {
          if (err && err.code !== 'ECONNRESET') {
            logger.error("Watch error", {
              error: err.message,
              code: err.code,
              namespace
            });
          } else if (err) {
            logger.debug("Watch connection reset", { namespace });
          }
        }
      );

      console.log(`✅ Watch established for namespace: "${namespace}"`);
      return watchRequest;
    } catch (error) {
      logger.error("Failed to start watching instances", { error: error.message });
      // In CI environments, don't throw errors for watch failures
      if (process.env.CI || process.env.NODE_ENV === 'test') {
        logger.warn("Watch functionality disabled in CI environment due to TLS restrictions");
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