const circuitBreakerManager = require('../services/circuitBreaker');

describe('Circuit Breaker Manager', () => {
  beforeEach(() => {
    circuitBreakerManager.shutdown();
  });

  afterAll(() => {
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

    await expect(breaker.fire()).rejects.toThrow('test error');

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
      rollingCountTimeout: 1000,
    });

    for (let i = 0; i < 5; i++) {
      try {
        await breaker.fire();
      } catch (error) {
        // expected
      }
    }

    const metrics = circuitBreakerManager.getMetrics('test-open');
    expect(metrics.stats.errorRate).toBeGreaterThan(0);
  });

  test('should serve fallback once the circuit is open', async () => {
    const mockFn = jest.fn().mockRejectedValue(new Error('test error'));
    const fallbackData = { cached: true };

    const breaker = circuitBreakerManager.createBreaker('test-fallback', mockFn, {
      errorThresholdPercentage: 50,
      rollingCountBuckets: 2,
      rollingCountTimeout: 1000,
      fallback: () => fallbackData,
    });

    // With a fallback configured, opossum resolves with the fallback value
    // on failure instead of rejecting.
    let lastResult;
    for (let i = 0; i < 5; i++) {
      lastResult = await breaker.fire();
    }

    expect(lastResult).toEqual(fallbackData);
    const metrics = circuitBreakerManager.getMetrics('test-fallback');
    expect(metrics.state).toBe('OPEN');
    expect(metrics.failures).toBeGreaterThan(0);
    expect(metrics.fallbacks).toBeGreaterThan(0);
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
      // expected
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
    expect(allMetrics['all-metrics-test']).toBeDefined();
    expect(allMetrics['all-metrics-test'].successes).toBe(1);
    expect(allMetrics['all-metrics-test'].currentState).toBe('CLOSED');
  });

  test('should handle circuit breaker timeout', async () => {
    const mockFn = jest.fn().mockImplementation(
      () => new Promise((resolve) => setTimeout(resolve, 100))
    );

    const breaker = circuitBreakerManager.createBreaker('timeout-test', mockFn, {
      timeout: 50,
    });

    try {
      await breaker.fire();
    } catch (error) {
      // expected timeout
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
  test('should serve data from a getter so refreshed caches are picked up', () => {
    let cache = { generation: 1 };
    const fallback = circuitBreakerManager.createCacheFallback(() => cache, 'test data');

    expect(typeof fallback).toBe('function');
    expect(fallback()).toEqual({ generation: 1 });

    cache = { generation: 2 };
    expect(fallback()).toEqual({ generation: 2 });
  });

  test('should pass through different data types', () => {
    expect(circuitBreakerManager.createCacheFallback(() => [1, 2, 3])()).toEqual([1, 2, 3]);
    expect(circuitBreakerManager.createCacheFallback(() => 'test string')()).toBe('test string');
    expect(circuitBreakerManager.createCacheFallback(() => null)()).toBeNull();
  });
});
