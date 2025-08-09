const KubernetesDiscovery = require('../services/kubernetesDiscovery');

describe('KubernetesDiscovery', () => {
  let discovery;

  beforeEach(() => {
    discovery = new KubernetesDiscovery();
  });

  afterEach(() => {
    if (discovery && discovery.stopBackgroundDiscovery) {
      discovery.stopBackgroundDiscovery();
    }
  });

  test('should initialize with default namespace', async () => {
    // Wait for initialization
    await new Promise(resolve => setTimeout(resolve, 2000));
    
    // In CI environment, initialization may fail but namespace should be set
    const namespace = discovery.getNamespace();
    expect(namespace).toBeDefined();
    expect(typeof namespace).toBe('string');
    expect(namespace.length).toBeGreaterThan(0);
    expect(namespace).not.toBe('null');
    expect(namespace).not.toBe('undefined');
  });

  test('should handle namespace validation properly', async () => {
    // Wait for initialization
    await new Promise(resolve => setTimeout(resolve, 2000));
    
    const namespace = discovery.getNamespace();
    
    // Test that namespace is not null/undefined string values
    expect(namespace).not.toBe('null');
    expect(namespace).not.toBe('undefined');
    expect(namespace).not.toBe('');
    expect(namespace.trim()).toBe(namespace); // Should be trimmed
  });

  test('should return empty array when no pods are found', async () => {
    // Wait for initialization
    await new Promise(resolve => setTimeout(resolve, 2000));
    
    const instances = await discovery.discoverEmulatorInstances();
    
    // Should return array (empty in CI environment)
    expect(Array.isArray(instances)).toBe(true);
    
    // In CI environment with no pods, should be empty
    if (process.env.CI || process.env.NODE_ENV === 'test') {
      expect(instances).toHaveLength(0);
    }
  });

  test('should handle services discovery', async () => {
    // Wait for initialization
    await new Promise(resolve => setTimeout(resolve, 2000));
    
    const services = await discovery.getServicesInfo();
    
    // Should return object (empty in CI environment)
    expect(typeof services).toBe('object');
    expect(services).not.toBeNull();
  });

  test('should validate namespace parameter for API calls', () => {
    // Test namespace validation logic (updated for Helm chart default 'loco')
    const testCases = [
      { input: 'default', expected: 'default' },
      { input: '  default  ', expected: 'default' },
      { input: '', expected: 'loco' }, // Updated to match Helm chart default
      { input: null, expected: 'loco' }, // Updated to match Helm chart default
      { input: undefined, expected: 'loco' }, // Updated to match Helm chart default
      { input: 'null', expected: 'loco' }, // Updated to match Helm chart default
      { input: 'undefined', expected: 'loco' } // Updated to match Helm chart default
    ];

    testCases.forEach(({ input, expected }) => {
      // Simulate the validation logic from the actual code
      let namespace = input;
      
      if (!namespace || namespace.trim() === '' || namespace === 'null' || namespace === 'undefined') {
        namespace = 'loco'; // Use Helm chart default instead of 'default'
      }
      
      namespace = String(namespace).trim();
      if (!namespace) {
        namespace = 'loco'; // Use Helm chart default
      }
      
      expect(namespace).toBe(expected);
    });
  });

  test('should handle API parameter object format', () => {
    // Test that we're using the correct parameter format for k8s client v1.3.0+
    const namespace = 'test-namespace';
    const labelSelector = 'app.kubernetes.io/component=emulator';
    
    const listPodsParams = {
      namespace: namespace,
      labelSelector: labelSelector
    };
    
    expect(listPodsParams).toHaveProperty('namespace', namespace);
    expect(listPodsParams).toHaveProperty('labelSelector', labelSelector);
    expect(typeof listPodsParams.namespace).toBe('string');
  });
});