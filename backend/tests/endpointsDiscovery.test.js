const EndpointsDiscovery = require('../services/endpointsDiscovery');

describe('EndpointsDiscovery', () => {
    let discovery;
    let mockK8sApi;
    let mockKc;
    let mockK8s;
    const namespace = 'test-namespace';
    const serviceName = 'test-service';

    beforeEach(() => {
        // Mock Kubernetes API client
        mockK8sApi = {
            readNamespacedEndpoints: jest.fn()
        };

        // Mock KubeConfig
        mockKc = {};

        // Mock k8s module with Watch class
        mockK8s = {
            Watch: jest.fn().mockImplementation(() => ({
                watch: jest.fn()
            }))
        };

        discovery = new EndpointsDiscovery(mockK8sApi, mockKc, mockK8s, namespace, serviceName);
    });

    describe('constructor', () => {
        it('should initialize with correct parameters', () => {
            expect(discovery.namespace).toBe(namespace);
            expect(discovery.serviceName).toBe(serviceName);
            expect(discovery.cachedEndpoints).toBeNull();
            expect(discovery.lastUpdate).toBeNull();
        });
    });

    describe('parseEndpoints', () => {
        it('should parse endpoints with ready addresses', () => {
            const mockEndpoints = {
                subsets: [{
                    addresses: [{
                        ip: '10.0.0.1',
                        hostname: 'pod-0',
                        nodeName: 'node-1',
                        targetRef: {
                            name: 'test-service-0',
                            kind: 'Pod'
                        }
                    }],
                    ports: [
                        { name: 'vnc', port: 5901 },
                        { name: 'health', port: 8080 }
                    ]
                }]
            };

            const instances = discovery.parseEndpoints(mockEndpoints);

            expect(instances).toHaveLength(1);
            expect(instances[0]).toMatchObject({
                id: 'instance-0',
                podName: 'test-service-0',
                addresses: {
                    podIP: '10.0.0.1',
                    hostname: 'pod-0',
                    dnsName: 'test-service-0.test-service.test-namespace.svc.cluster.local'
                },
                ports: {
                    vnc: 5901,
                    health: 8080
                },
                health: {
                    ready: true
                },
                status: 'ready'
            });
        });

        it('should parse endpoints with not-ready addresses', () => {
            const mockEndpoints = {
                subsets: [{
                    notReadyAddresses: [{
                        ip: '10.0.0.2',
                        hostname: 'pod-1',
                        nodeName: 'node-1',
                        targetRef: {
                            name: 'test-service-1',
                            kind: 'Pod'
                        }
                    }],
                    ports: [
                        { name: 'vnc', port: 5901 }
                    ]
                }]
            };

            const instances = discovery.parseEndpoints(mockEndpoints);

            expect(instances).toHaveLength(1);
            expect(instances[0]).toMatchObject({
                id: 'instance-1',
                podName: 'test-service-1',
                health: {
                    ready: false
                },
                status: 'not-ready'
            });
        });

        it('should handle mixed ready and not-ready addresses', () => {
            const mockEndpoints = {
                subsets: [{
                    addresses: [{
                        ip: '10.0.0.1',
                        targetRef: { name: 'test-service-0' }
                    }],
                    notReadyAddresses: [{
                        ip: '10.0.0.2',
                        targetRef: { name: 'test-service-1' }
                    }],
                    ports: [{ name: 'vnc', port: 5901 }]
                }]
            };

            const instances = discovery.parseEndpoints(mockEndpoints);

            expect(instances).toHaveLength(2);
            expect(instances[0].health.ready).toBe(true);
            expect(instances[1].health.ready).toBe(false);
        });

        it('should return empty array for empty subsets', () => {
            const mockEndpoints = { subsets: [] };
            const instances = discovery.parseEndpoints(mockEndpoints);
            expect(instances).toEqual([]);
        });

        it('should return empty array for undefined subsets', () => {
            const mockEndpoints = {};
            const instances = discovery.parseEndpoints(mockEndpoints);
            expect(instances).toEqual([]);
        });

        it('should sort instances by instance number', () => {
            const mockEndpoints = {
                subsets: [{
                    addresses: [
                        { ip: '10.0.0.3', targetRef: { name: 'test-service-2' } },
                        { ip: '10.0.0.1', targetRef: { name: 'test-service-0' } },
                        { ip: '10.0.0.2', targetRef: { name: 'test-service-1' } }
                    ],
                    ports: []
                }]
            };

            const instances = discovery.parseEndpoints(mockEndpoints);

            expect(instances).toHaveLength(3);
            expect(instances[0].id).toBe('instance-0');
            expect(instances[1].id).toBe('instance-1');
            expect(instances[2].id).toBe('instance-2');
        });
    });

    describe('extractInstanceNumber', () => {
        it('should extract instance number from pod name', () => {
            expect(discovery.extractInstanceNumber('test-service-0')).toBe(0);
            expect(discovery.extractInstanceNumber('test-service-5')).toBe(5);
            expect(discovery.extractInstanceNumber('test-service-42')).toBe(42);
        });

        it('should return 0 for pod name without number', () => {
            expect(discovery.extractInstanceNumber('test-service')).toBe(0);
            expect(discovery.extractInstanceNumber('unknown')).toBe(0);
        });
    });

    describe('mapPorts', () => {
        it('should map ports array to object', () => {
            const ports = [
                { name: 'vnc', port: 5901 },
                { name: 'health', port: 8080 },
                { name: 'metrics', port: 9090 }
            ];

            const portMap = discovery.mapPorts(ports);

            expect(portMap).toEqual({
                vnc: 5901,
                health: 8080,
                metrics: 9090
            });
        });

        it('should return empty object for empty ports array', () => {
            expect(discovery.mapPorts([])).toEqual({});
        });

        it('should return empty object for undefined ports', () => {
            expect(discovery.mapPorts(undefined)).toEqual({});
        });

        it('should skip ports without names', () => {
            const ports = [
                { name: 'vnc', port: 5901 },
                { port: 8080 }, // no name
                { name: 'metrics', port: 9090 }
            ];

            const portMap = discovery.mapPorts(ports);

            expect(portMap).toEqual({
                vnc: 5901,
                metrics: 9090
            });
        });
    });

    describe('createInstance', () => {
        it('should create instance object with all fields', () => {
            const address = {
                ip: '10.0.0.1',
                hostname: 'pod-0',
                nodeName: 'node-1',
                targetRef: {
                    name: 'test-service-0',
                    kind: 'Pod',
                    namespace: 'test'
                }
            };
            const ports = [
                { name: 'vnc', port: 5901 },
                { name: 'health', port: 8080 }
            ];

            const instance = discovery.createInstance(address, ports, true);

            expect(instance).toMatchObject({
                id: 'instance-0',
                name: 'Windows 98 - Game Server',
                podName: 'test-service-0',
                addresses: {
                    podIP: '10.0.0.1',
                    hostname: 'pod-0',
                    dnsName: 'test-service-0.test-service.test-namespace.svc.cluster.local'
                },
                ports: {
                    vnc: 5901,
                    health: 8080
                },
                health: {
                    ready: true
                },
                status: 'ready',
                provisioned: true,
                kubernetes: {
                    namespace: 'test-namespace',
                    nodeName: 'node-1',
                    targetRef: address.targetRef
                }
            });

            expect(instance.discoveredAt).toBeDefined();
            expect(instance.streamUrl).toBeDefined();
            expect(instance.vncUrl).toBeDefined();
            expect(instance.healthUrl).toBeDefined();
        });

        it('should set correct name for instance 0', () => {
            const address = {
                ip: '10.0.0.1',
                targetRef: { name: 'test-service-0' }
            };

            const instance = discovery.createInstance(address, [], true);
            expect(instance.name).toBe('Windows 98 - Game Server');
        });

        it('should set correct name for instance > 0', () => {
            const address = {
                ip: '10.0.0.1',
                targetRef: { name: 'test-service-1' }
            };

            const instance = discovery.createInstance(address, [], true);
            expect(instance.name).toBe('Windows 98 - Client 1');
        });

        it('should handle missing targetRef gracefully', () => {
            const address = {
                ip: '10.0.0.1'
            };

            const instance = discovery.createInstance(address, [], true);
            expect(instance.podName).toBe('unknown');
            expect(instance.id).toBe('instance-0');
        });
    });

    describe('discoverInstances', () => {
        it('should successfully discover instances', async () => {
            const mockResponse = {
                body: {
                    subsets: [{
                        addresses: [{
                            ip: '10.0.0.1',
                            targetRef: { name: 'test-service-0' }
                        }],
                        ports: [{ name: 'vnc', port: 5901 }]
                    }]
                }
            };

            mockK8sApi.readNamespacedEndpoints.mockResolvedValue(mockResponse);

            const instances = await discovery.discoverInstances();

            expect(mockK8sApi.readNamespacedEndpoints).toHaveBeenCalledWith({
                name: serviceName,
                namespace: namespace
            });
            expect(instances).toHaveLength(1);
            expect(instances[0].id).toBe('instance-0');
            expect(discovery.cachedEndpoints).toBe(mockResponse.body);
            expect(discovery.lastUpdate).toBeInstanceOf(Date);
        });

        it('should return empty array when no response body', async () => {
            mockK8sApi.readNamespacedEndpoints.mockResolvedValue({});

            const instances = await discovery.discoverInstances();

            expect(instances).toEqual([]);
        });

        it('should return empty array on API error', async () => {
            mockK8sApi.readNamespacedEndpoints.mockRejectedValue(new Error('API error'));

            const instances = await discovery.discoverInstances();

            expect(instances).toEqual([]);
        });

        it('should cache discovered endpoints', async () => {
            const mockResponse = {
                body: {
                    subsets: [{
                        addresses: [{ ip: '10.0.0.1', targetRef: { name: 'test-0' } }],
                        ports: []
                    }]
                }
            };

            mockK8sApi.readNamespacedEndpoints.mockResolvedValue(mockResponse);

            await discovery.discoverInstances();

            expect(discovery.getCachedEndpoints()).toBe(mockResponse.body);
            expect(discovery.getLastUpdate()).toBeInstanceOf(Date);
        });
    });

    describe('watchEndpoints', () => {
        it('should set up watch for endpoints changes', async () => {
            const mockWatch = {
                watch: jest.fn().mockResolvedValue({})
            };
            mockK8s.Watch.mockReturnValue(mockWatch);

            const callback = jest.fn();
            await discovery.watchEndpoints(callback);

            expect(mockK8s.Watch).toHaveBeenCalledWith(mockKc);
            expect(mockWatch.watch).toHaveBeenCalledWith(
                `/api/v1/namespaces/${namespace}/endpoints/${serviceName}`,
                {},
                expect.any(Function),
                expect.any(Function)
            );
        });

        it('should trigger callback on endpoint changes', async () => {
            let watchCallback;
            const mockWatch = {
                watch: jest.fn().mockImplementation((path, opts, cb, errCb) => {
                    watchCallback = cb;
                    return Promise.resolve({});
                })
            };
            mockK8s.Watch.mockReturnValue(mockWatch);

            const callback = jest.fn();
            await discovery.watchEndpoints(callback);

            // Simulate endpoint change
            const mockEndpoint = { metadata: { name: 'test-service' } };
            watchCallback('MODIFIED', mockEndpoint);

            expect(callback).toHaveBeenCalledWith('MODIFIED', mockEndpoint);
        });

        it('should handle callback errors gracefully', async () => {
            let watchCallback;
            const mockWatch = {
                watch: jest.fn().mockImplementation((path, opts, cb, errCb) => {
                    watchCallback = cb;
                    return Promise.resolve({});
                })
            };
            mockK8s.Watch.mockReturnValue(mockWatch);

            const callback = jest.fn().mockImplementation(() => {
                throw new Error('Callback error');
            });
            await discovery.watchEndpoints(callback);

            // Should not throw
            expect(() => {
                watchCallback('MODIFIED', {});
            }).not.toThrow();
        });

        it('should return null on watch setup error', async () => {
            mockK8s.Watch.mockImplementation(() => {
                throw new Error('Watch error');
            });

            const result = await discovery.watchEndpoints(jest.fn());

            expect(result).toBeNull();
        });
    });

    describe('getCachedEndpoints', () => {
        it('should return cached endpoints', () => {
            const mockEndpoints = { subsets: [] };
            discovery.cachedEndpoints = mockEndpoints;

            expect(discovery.getCachedEndpoints()).toBe(mockEndpoints);
        });

        it('should return null when no cache', () => {
            expect(discovery.getCachedEndpoints()).toBeNull();
        });
    });

    describe('getLastUpdate', () => {
        it('should return last update timestamp', () => {
            const now = new Date();
            discovery.lastUpdate = now;

            expect(discovery.getLastUpdate()).toBe(now);
        });

        it('should return null when no update', () => {
            expect(discovery.getLastUpdate()).toBeNull();
        });
    });
});
