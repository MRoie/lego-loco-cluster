const CircuitBreaker = require('opossum');
const logger = require('../utils/logger');

/**
 * Circuit breaker manager for external dependencies (concept from PR #79).
 *
 * Wraps functions with opossum circuit breakers, collects per-breaker
 * metrics, and provides cached-data fallbacks so the backend keeps serving
 * last-known-good data when an external service (the Kubernetes API) is
 * unavailable instead of cascading the failure.
 */
class CircuitBreakerManager {
  constructor() {
    this.breakers = new Map();
    this.metrics = new Map();

    this.defaultOptions = {
      timeout: 10000, // 10s — k8s API calls can be slow on loaded clusters
      errorThresholdPercentage: 60, // trip at 60% error rate
      resetTimeout: 30000, // 30s before attempting half-open
      rollingCountTimeout: 60000, // 1 minute rolling window
      rollingCountBuckets: 10,
    };
  }

  /**
   * Create (or return an existing) circuit breaker for a function.
   * @param {string} name - unique breaker name
   * @param {Function} fn - async function to protect
   * @param {Object} [options] - opossum option overrides (+ optional fallback)
   * @returns {CircuitBreaker}
   */
  createBreaker(name, fn, options = {}) {
    if (this.breakers.has(name)) {
      return this.breakers.get(name);
    }

    const { fallback, ...opossumOptions } = options;
    const breaker = new CircuitBreaker(fn, {
      ...this.defaultOptions,
      ...opossumOptions,
      name,
    });

    if (typeof fallback === 'function') {
      breaker.fallback(fallback);
    }

    this.setupEventListeners(breaker, name);
    this.breakers.set(name, breaker);
    logger.info('Circuit breaker created', { breaker: name });
    return breaker;
  }

  setupEventListeners(breaker, name) {
    this.metrics.set(name, {
      state: 'CLOSED',
      failures: 0,
      successes: 0,
      timeouts: 0,
      opens: 0,
      halfOpens: 0,
      closes: 0,
      fallbacks: 0,
      lastStateChange: new Date().toISOString(),
      stats: {
        totalRequests: 0,
        totalFailures: 0,
        totalSuccesses: 0,
        errorRate: 0,
      },
    });

    const metrics = this.metrics.get(name);

    breaker.on('open', () => {
      metrics.state = 'OPEN';
      metrics.opens++;
      metrics.lastStateChange = new Date().toISOString();
      logger.warn('Circuit breaker opened', { breaker: name });
    });

    breaker.on('halfOpen', () => {
      metrics.state = 'HALF_OPEN';
      metrics.halfOpens++;
      metrics.lastStateChange = new Date().toISOString();
      logger.info('Circuit breaker half-open', { breaker: name });
    });

    breaker.on('close', () => {
      metrics.state = 'CLOSED';
      metrics.closes++;
      metrics.lastStateChange = new Date().toISOString();
      logger.info('Circuit breaker closed', { breaker: name });
    });

    breaker.on('success', () => {
      metrics.successes++;
      metrics.stats.totalSuccesses++;
      metrics.stats.totalRequests++;
      this.updateStats(metrics);
    });

    breaker.on('failure', (error) => {
      metrics.failures++;
      metrics.stats.totalFailures++;
      metrics.stats.totalRequests++;
      this.updateStats(metrics);
      logger.warn('Circuit breaker failure', { breaker: name, error: error?.message });
    });

    breaker.on('timeout', () => {
      metrics.timeouts++;
      metrics.stats.totalFailures++;
      metrics.stats.totalRequests++;
      this.updateStats(metrics);
      logger.warn('Circuit breaker timeout', { breaker: name });
    });

    breaker.on('fallback', () => {
      metrics.fallbacks++;
      logger.info('Circuit breaker fallback served', { breaker: name });
    });
  }

  updateStats(metrics) {
    const { totalRequests, totalFailures } = metrics.stats;
    metrics.stats.errorRate = totalRequests > 0 ? (totalFailures / totalRequests) * 100 : 0;
  }

  getBreaker(name) {
    return this.breakers.get(name) || null;
  }

  getMetrics(name) {
    return this.metrics.get(name) || null;
  }

  getAllMetrics() {
    const allMetrics = {};
    for (const [name, metrics] of this.metrics) {
      const breaker = this.breakers.get(name);
      allMetrics[name] = {
        ...metrics,
        currentState: breaker?.opened ? 'OPEN' : breaker?.halfOpen ? 'HALF_OPEN' : 'CLOSED',
      };
    }
    return allMetrics;
  }

  getSummary() {
    const summary = {
      totalBreakers: this.breakers.size,
      openBreakers: 0,
      halfOpenBreakers: 0,
      closedBreakers: 0,
      totalRequests: 0,
      totalFailures: 0,
      overallErrorRate: 0,
    };

    for (const [name, metrics] of this.metrics) {
      const breaker = this.breakers.get(name);
      if (breaker?.opened) summary.openBreakers++;
      else if (breaker?.halfOpen) summary.halfOpenBreakers++;
      else summary.closedBreakers++;

      summary.totalRequests += metrics.stats.totalRequests;
      summary.totalFailures += metrics.stats.totalFailures;
    }

    summary.overallErrorRate =
      summary.totalRequests > 0 ? (summary.totalFailures / summary.totalRequests) * 100 : 0;

    return summary;
  }

  /**
   * Build a fallback that serves data from a getter at open-circuit time
   * (a getter, not a snapshot — the cache may be refreshed between trips).
   */
  createCacheFallback(getCachedData, description = 'cached data') {
    return () => {
      logger.info('Serving circuit breaker fallback', { source: description });
      return getCachedData();
    };
  }

  shutdown() {
    for (const [name, breaker] of this.breakers) {
      try {
        breaker.shutdown();
        logger.info('Circuit breaker shut down', { breaker: name });
      } catch (error) {
        logger.warn('Failed to shut down circuit breaker', { breaker: name, error: error.message });
      }
    }
    this.breakers.clear();
    this.metrics.clear();
  }
}

// Singleton shared across the backend
module.exports = new CircuitBreakerManager();
module.exports.CircuitBreakerManager = CircuitBreakerManager;
