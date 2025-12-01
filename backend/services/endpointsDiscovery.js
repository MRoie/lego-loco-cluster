const logger = require('../utils/logger');

/**
 * EndpointsDiscovery - Kubernetes Endpoints-based service discovery
 * 
 * This class discovers emulator instances by querying the Kubernetes Endpoints API
 * instead of directly querying Pods. This provides:
 * - Health-aware discovery (only ready endpoints are included)
 * - Simpler API with guaranteed response structure
 * - Automatic DNS name construction
 * - Better resilience during rolling updates
 */
class EndpointsDiscovery {
    /**
     * @param {Object} k8sApi - Kubernetes CoreV1Api client
     * @param {Object} kc - KubeConfig instance
     * @param {Object} k8s - Kubernetes client-node module
     * @param {string} namespace - Kubernetes namespace
     * @param {string} serviceName - Name of the Service to query endpoints for
     */
    constructor(k8sApi, kc, k8s, namespace, serviceName) {
        this.k8sApi = k8sApi;
        this.kc = kc;
        this.k8s = k8s;
        this.namespace = namespace;
        this.serviceName = serviceName;
        this.cachedEndpoints = null;
        this.lastUpdate = null;
    }

    /**
     * Discover emulator instances from Endpoints API
     * @returns {Promise<Array>} Array of instance objects
     */
    async discoverInstances() {
        try {
            logger.info('Discovering instances via Endpoints API', {
                namespace: this.namespace,
                serviceName: this.serviceName
            });

            const endpoints = await this.k8sApi.readNamespacedEndpoints({
                name: this.serviceName,
                namespace: this.namespace
            });

            if (!endpoints || !endpoints.body) {
                logger.warn('No endpoints response from Kubernetes API');
                return [];
            }

            const instances = this.parseEndpoints(endpoints.body);

            // Update cache
            this.cachedEndpoints = endpoints.body;
            this.lastUpdate = new Date();

            logger.info('Discovered instances via Endpoints API', {
                count: instances.length,
                ready: instances.filter(i => i.health.ready).length,
                notReady: instances.filter(i => !i.health.ready).length
            });

            return instances;
        } catch (error) {
            logger.error('Failed to discover instances from Endpoints', {
                error: error.message,
                stack: error.stack,
                namespace: this.namespace,
                serviceName: this.serviceName
            });
            return [];
        }
    }

    /**
     * Parse Endpoints object into instance array
     * @param {Object} endpoints - Kubernetes Endpoints object
     * @returns {Array} Array of instance objects
     */
    parseEndpoints(endpoints) {
        const instances = [];

        if (!endpoints.subsets || endpoints.subsets.length === 0) {
            logger.warn('No endpoint subsets found', {
                serviceName: this.serviceName,
                namespace: this.namespace
            });
            return instances;
        }

        for (const subset of endpoints.subsets) {
            // Process ready addresses
            if (subset.addresses && subset.addresses.length > 0) {
                for (const address of subset.addresses) {
                    instances.push(this.createInstance(address, subset.ports, true));
                }
            }

            // Process not-ready addresses (for monitoring purposes)
            if (subset.notReadyAddresses && subset.notReadyAddresses.length > 0) {
                for (const address of subset.notReadyAddresses) {
                    instances.push(this.createInstance(address, subset.ports, false));
                }
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

    /**
     * Create instance object from endpoint address
     * @param {Object} address - Endpoint address object
     * @param {Array} ports - Array of port objects
     * @param {boolean} ready - Whether the endpoint is ready
     * @returns {Object} Instance object
     */
    createInstance(address, ports, ready) {
        const podName = address.targetRef?.name || 'unknown';
        const instanceNumber = this.extractInstanceNumber(podName);

        const instance = {
            id: `instance-${instanceNumber}`,
            name: `Windows 98 - ${instanceNumber === 0 ? 'Game Server' : `Client ${instanceNumber}`}`,
            description: instanceNumber === 0
                ? 'Primary gaming instance with full Lego Loco installation'
                : 'Player client instance',
            podName: podName,
            addresses: {
                podIP: address.ip,
                hostname: address.hostname || podName,
                dnsName: `${podName}.${this.serviceName}.${this.namespace}.svc.cluster.local`
            },
            ports: this.mapPorts(ports),
            health: {
                ready: ready,
                lastTransition: new Date().toISOString()
            },
            status: ready ? 'ready' : 'not-ready',
            provisioned: true,
            discoveredAt: new Date().toISOString(),
            kubernetes: {
                namespace: this.namespace,
                nodeName: address.nodeName,
                targetRef: address.targetRef
            }
        };

        // Add URLs for compatibility with existing code
        const vncPort = this.mapPorts(ports).vnc || 5901;
        const healthPort = this.mapPorts(ports).health || 8080;

        instance.streamUrl = `http://localhost:${6080 + instanceNumber}/vnc${instanceNumber}`;
        instance.vncUrl = `${podName}:${vncPort}`;
        instance.healthUrl = `http://${address.ip}:${healthPort}`;

        return instance;
    }

    /**
     * Map port array to port object
     * @param {Array} ports - Array of port objects from Endpoints
     * @returns {Object} Port map (name -> port number)
     */
    mapPorts(ports) {
        const portMap = {};

        if (!ports || ports.length === 0) {
            return portMap;
        }

        for (const port of ports) {
            if (port.name) {
                portMap[port.name] = port.port;
            }
        }

        return portMap;
    }

    /**
     * Extract instance number from pod name
     * @param {string} podName - Pod name (e.g., "loco-loco-emulator-0")
     * @returns {number} Instance number
     */
    extractInstanceNumber(podName) {
        const match = podName.match(/-(\d+)$/);
        return match ? parseInt(match[1]) : 0;
    }

    /**
     * Watch Endpoints for changes
     * @param {Function} callback - Callback function(type, endpoint)
     * @returns {Promise<Object>} Watch request object
     */
    async watchEndpoints(callback) {
        try {
            logger.info('Starting watch for Endpoints changes', {
                namespace: this.namespace,
                serviceName: this.serviceName
            });

            const watch = new this.k8s.Watch(this.kc);

            const watchRequest = await watch.watch(
                `/api/v1/namespaces/${this.namespace}/endpoints/${this.serviceName}`,
                {},
                (type, endpoint) => {
                    logger.debug('Endpoints changed', {
                        type,
                        service: this.serviceName,
                        namespace: this.namespace
                    });

                    // Trigger callback to refresh instance list
                    if (callback && typeof callback === 'function') {
                        try {
                            callback(type, endpoint);
                        } catch (callbackError) {
                            logger.error('Watch callback error', {
                                error: callbackError.message,
                                stack: callbackError.stack
                            });
                        }
                    }
                },
                (err) => {
                    if (err && err.code !== 'ECONNRESET') {
                        logger.error('Endpoints watch error', {
                            error: err.message,
                            code: err.code,
                            namespace: this.namespace,
                            serviceName: this.serviceName
                        });
                    } else if (err) {
                        logger.debug('Endpoints watch connection reset', {
                            namespace: this.namespace,
                            serviceName: this.serviceName
                        });
                    }
                }
            );

            logger.info('Endpoints watch established', {
                namespace: this.namespace,
                serviceName: this.serviceName
            });

            return watchRequest;
        } catch (error) {
            logger.error('Failed to start watching Endpoints', {
                error: error.message,
                stack: error.stack,
                namespace: this.namespace,
                serviceName: this.serviceName
            });
            return null;
        }
    }

    /**
     * Get cached endpoints (for debugging/monitoring)
     * @returns {Object|null} Cached endpoints object
     */
    getCachedEndpoints() {
        return this.cachedEndpoints;
    }

    /**
     * Get last update timestamp
     * @returns {Date|null} Last update timestamp
     */
    getLastUpdate() {
        return this.lastUpdate;
    }
}

module.exports = EndpointsDiscovery;
