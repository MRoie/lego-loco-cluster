const k8s = require('@kubernetes/client-node');
const fs = require('fs');
const path = require('path');

class KubernetesDiscovery {
  constructor() {
    this.kc = new k8s.KubeConfig();
    this.k8sApi = null;
    this.namespace = 'default';
    this.initialized = false;
    
    this.init();
  }

  init() {
    try {
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
      this.initialized = true;
      
      // Try to detect namespace from environment or service account
      if (process.env.KUBERNETES_NAMESPACE) {
        this.namespace = process.env.KUBERNETES_NAMESPACE;
      } else if (fs.existsSync('/var/run/secrets/kubernetes.io/serviceaccount/namespace')) {
        this.namespace = fs.readFileSync('/var/run/secrets/kubernetes.io/serviceaccount/namespace', 'utf8').trim();
      }
      
      console.log(`Kubernetes discovery initialized for namespace: ${this.namespace}`);
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

    try {
      // Discover StatefulSet pods with emulator label
      const podsResponse = await this.k8sApi.listNamespacedPod(
        this.namespace,
        undefined, // pretty
        undefined, // allowWatchBookmarks
        undefined, // continue
        undefined, // fieldSelector
        'app.kubernetes.io/component=emulator,app.kubernetes.io/part-of=lego-loco-cluster' // labelSelector
      );

      const instances = [];
      
      for (const pod of podsResponse.body.items) {
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
          
          instances.push(instance);
        }
      }

      // Sort instances by instance number
      instances.sort((a, b) => {
        const aNum = parseInt(a.id.split('-')[1]);
        const bNum = parseInt(b.id.split('-')[1]);
        return aNum - bNum;
      });

      console.log(`Discovered ${instances.length} emulator instances from Kubernetes`);
      return instances;
      
    } catch (error) {
      console.error('Failed to discover instances from Kubernetes:', error.message);
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

    try {
      const servicesResponse = await this.k8sApi.listNamespacedService(
        this.namespace,
        undefined, // pretty
        undefined, // allowWatchBookmarks
        undefined, // continue
        undefined, // fieldSelector
        'app.kubernetes.io/part-of=lego-loco-cluster' // labelSelector
      );

      const services = {};
      
      for (const service of servicesResponse.body.items) {
        services[service.metadata.name] = {
          name: service.metadata.name,
          type: service.spec.type,
          clusterIP: service.spec.clusterIP,
          ports: service.spec.ports,
          selector: service.spec.selector
        };
      }

      return services;
    } catch (error) {
      console.error('Failed to get services info:', error.message);
      return {};
    }
  }

  async watchEmulatorInstances(callback) {
    if (!this.initialized) {
      console.warn('Cannot watch instances: Kubernetes discovery not initialized');
      return null;
    }

    try {
      const watch = new k8s.Watch(this.kc);
      
      console.log('Starting watch for emulator pod changes...');
      
      const watchRequest = watch.watch(
        `/api/v1/namespaces/${this.namespace}/pods`,
        { labelSelector: 'app.kubernetes.io/component=emulator,app.kubernetes.io/part-of=lego-loco-cluster' },
        (type, apiObj) => {
          console.log(`Pod ${type}: ${apiObj.metadata.name} - ${apiObj.status.phase}`);
          
          // Trigger callback to refresh instance list
          if (callback) {
            callback(type, apiObj);
          }
        },
        (err) => {
          console.error('Watch error:', err);
        }
      );

      return watchRequest;
    } catch (error) {
      console.error('Failed to start watching instances:', error.message);
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