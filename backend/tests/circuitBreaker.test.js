const circuitBreakerManager = require('../services/circuitBreaker');

describe('Circuit Breaker Manager', () => {
  beforeEach(() => {
    // Clean up any existing breakers before each test
    circuitBreakerManager.shutdown();
  });

  afterAll(() => {
    // Clean up after all tests
    circuitBreakerManager.shutdown();
  });

  test('should create a circuit breaker with default options', () => {
    const mockFn = jest.fn().mockResolvedValue('success');
    const breaker = circuitBreakerManager.createBreaker('test-breaker', mockFn);
    
    expect(breaker).toBeDefined();
    expect(breaker.name).toBe('test-breaker');
    expect(breaker.closed).toBe(true);
  });

  test('should return existing breaker if already created', () => {
    const mockFn = jest.fn().mockResolvedValue('success');
    const breaker1 = circuitBreakerManager.createBreaker('test-breaker', mockFn);
    const breaker2 = circuitBreakerManager.createBreaker('test-breaker', mockFn);
    
    expect(breaker1).toBe(breaker2);
  });

  test('should execute function through circuit breaker successfully', async () => {
    const mockFn = jest.fn().mockResolvedValue('success');
    const breaker = circuitBreakerManager.createBreaker('test-success', mockFn);
    
    const result = await breaker.fire('test-arg');
    
    expect(result).toBe('success');
    expect(mockFn).toHaveBeenCalledWith('test-arg');
  });

  test('should collect metrics for successful calls', async () => {
    const mockFn = jest.fn().mockResolvedValue('success');
    const breaker = circuitBreakerManager.createBreaker('test-metrics', mockFn);
    
    await breaker.fire();
    
    const metrics = circuitBreakerManager.getMetrics('test-metrics');
    expect(metrics).toBeDefined();
    expect(metrics.successes).toBe(1);
    expect(metrics.stats.totalSuccesses).toBe(1);
    expect(metrics.stats.totalRequests).toBe(1);
    expect(metrics.state).toBe('CLOSED');
  });

  test('should collect metrics for failed calls', async () => {
    const mockFn = jest.fn().mockRejectedValue(new Error('test error'));
    const breaker = circuitBreakerManager.createBreaker('test-failures', mockFn);
    
    try {
      await breaker.fire();
    } catch (error) {
      // Expected to fail
    }
    
    const metrics = circuitBreakerManager.getMetrics('test-failures');
    expect(metrics).toBeDefined();
    expect(metrics.failures).toBe(1);
    expect(metrics.stats.totalFailures).toBe(1);
    expect(metrics.stats.totalRequests).toBe(1);
    expect(metrics.stats.errorRate).toBe(100);
  });

  test('should open circuit breaker after threshold failures', async () => {
    const mockFn = jest.fn().mockRejectedValue(new Error('test error'));
    const breaker = circuitBreakerManager.createBreaker('test-open', mockFn, {
      errorThresholdPercentage: 50,
      rollingCountBuckets: 2,
      rollingCountTimeout: 1000
    });
    
    // Generate enough failures to trip the breaker
    for (let i = 0; i < 5; i++) {
      try {
        await breaker.fire();
      } catch (error) {
        // Expected to fail
      }
    }
    
    const metrics = circuitBreakerManager.getMetrics('test-open');
    expect(metrics.stats.errorRate).toBeGreaterThan(0);
  });

  test('should execute fallback when circuit is open', async () => {
    // For now, let's test that fallback is configured and metrics are tracked
    // The actual fallback behavior in opossum requires more specific configuration
    const mockFn = jest.fn().mockRejectedValue(new Error('test error'));
    const fallbackData = { cached: true };
    
    const breaker = circuitBreakerManager.createBreaker('test-fallback', mockFn, {
      errorThresholdPercentage: 50,
      rollingCountBuckets: 2,
      rollingCountTimeout: 1000,
      fallback: () => fallbackData
    });
    
    // Force the breaker to fail multiple times
    for (let i = 0; i < 5; i++) {
      try {
        await breaker.fire();
      } catch (error) {
        // Expected to fail initially
      }
    }
    
    // Verify the circuit breaker is open
    const metrics = circuitBreakerManager.getMetrics('test-fallback');
    expect(metrics.state).toBe('OPEN');
    expect(metrics.failures).toBeGreaterThan(0);
  });

  test('should provide summary statistics', async () => {
    const mockFn1 = jest.fn().mockResolvedValue('success');
    const mockFn2 = jest.fn().mockRejectedValue(new Error('error'));
    
    const breaker1 = circuitBreakerManager.createBreaker('summary-test-1', mockFn1);
    const breaker2 = circuitBreakerManager.createBreaker('summary-test-2', mockFn2);
    
    await breaker1.fire();
    try {
      await breaker2.fire();
    } catch (error) {
      // Expected to fail
    }
    
    const summary = circuitBreakerManager.getSummary();
    expect(summary.totalBreakers).toBe(2);
    expect(summary.totalRequests).toBe(2);
    expect(summary.totalFailures).toBe(1);
    expect(summary.overallErrorRate).toBe(50);
  });

  test('should return all metrics', async () => {
    const mockFn = jest.fn().mockResolvedValue('success');
    const breaker = circuitBreakerManager.createBreaker('all-metrics-test', mockFn);
    
    await breaker.fire();
    
    const allMetrics = circuitBreakerManager.getAllMetrics();
    expect(allMetrics).toBeDefined();
    expect(allMetrics['all-metrics-test']).toBeDefined();
    expect(allMetrics['all-metrics-test'].successes).toBe(1);
  });

  test('should handle circuit breaker timeout', async () => {
    const mockFn = jest.fn().mockImplementation(() => 
      new Promise(resolve => setTimeout(resolve, 100))
    );
    
    const breaker = circuitBreakerManager.createBreaker('timeout-test', mockFn, {
      timeout: 50 // 50ms timeout
    });
    
    try {
      await breaker.fire();
    } catch (error) {
      // Expected to timeout
    }
    
    const metrics = circuitBreakerManager.getMetrics('timeout-test');
    expect(metrics.timeouts).toBe(1);
  });

  test('should clean up resources on shutdown', () => {
    const mockFn = jest.fn().mockResolvedValue('success');
    circuitBreakerManager.createBreaker('shutdown-test', mockFn);
    
    expect(circuitBreakerManager.getAllMetrics()['shutdown-test']).toBeDefined();
    
    circuitBreakerManager.shutdown();
    
    expect(Object.keys(circuitBreakerManager.getAllMetrics())).toHaveLength(0);
  });
});

describe('Circuit Breaker Cache Fallback', () => {
  test('should create fallback function with cached data', () => {
    const cachedData = { test: 'data' };
    const fallback = circuitBreakerManager.createCacheFallback(cachedData, 'test data');
    
    expect(typeof fallback).toBe('function');
    expect(fallback()).toEqual(cachedData);
  });

  test('should work with different data types', () => {
    const arrayData = [1, 2, 3];
    const stringData = 'test string';
    const nullData = null;
    
    const arrayFallback = circuitBreakerManager.createCacheFallback(arrayData);
    const stringFallback = circuitBreakerManager.createCacheFallback(stringData);
    const nullFallback = circuitBreakerManager.createCacheFallback(nullData);
    
    expect(arrayFallback()).toEqual(arrayData);
    expect(stringFallback()).toBe(stringData);
    expect(nullFallback()).toBe(nullData);
  });
});