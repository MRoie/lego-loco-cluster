const CircuitBreaker = require('opossum');

class CircuitBreakerManager {
  constructor() {
    this.breakers = new Map();
    this.metrics = new Map();
    
    // Default circuit breaker options
    this.defaultOptions = {
      timeout: 5000, // 5 seconds timeout for external calls
      errorThresholdPercentage: 50, // Trip at 50% error rate
      resetTimeout: 30000, // 30 seconds before attempting reset
      rollingCountTimeout: 60000, // 1 minute rolling window
      rollingCountBuckets: 10, // 10 buckets for rolling count
      name: 'default',
      fallback: null // Fallback function to execute when circuit is open
    };
  }

  /**
   * Create or get a circuit breaker for a specific function
   * @param {string} name - Unique name for the circuit breaker
   * @param {Function} fn - Function to wrap with circuit breaker
   * @param {Object} options - Circuit breaker options
   * @returns {CircuitBreaker} Circuit breaker instance
   */
  createBreaker(name, fn, options = {}) {
    if (this.breakers.has(name)) {
      return this.breakers.get(name);
    }

    const breakerOptions = {
      ...this.defaultOptions,
      ...options,
      name
    };

    const breaker = new CircuitBreaker(fn, breakerOptions);

    // Set up event listeners for metrics collection
    this.setupEventListeners(breaker, name);

    // Store the breaker
    this.breakers.set(name, breaker);

    console.log(`🔧 Circuit breaker created: ${name}`);
    return breaker;
  }

  /**
   * Set up event listeners for a circuit breaker to collect metrics
   * @param {CircuitBreaker} breaker - Circuit breaker instance
   * @param {string} name - Breaker name
   */
  setupEventListeners(breaker, name) {
    // Initialize metrics
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
        averageResponseTime: 0,
        errorRate: 0
      }
    });

    const metrics = this.metrics.get(name);

    // State change events
    breaker.on('open', () => {
      metrics.state = 'OPEN';
      metrics.opens++;
      metrics.lastStateChange = new Date().toISOString();
      console.log(`⚠️  Circuit breaker OPENED: ${name}`);
    });

    breaker.on('halfOpen', () => {
      metrics.state = 'HALF_OPEN';
      metrics.halfOpens++;
      metrics.lastStateChange = new Date().toISOString();
      console.log(`🔄 Circuit breaker HALF-OPEN: ${name}`);
    });

    breaker.on('close', () => {
      metrics.state = 'CLOSED';
      metrics.closes++;
      metrics.lastStateChange = new Date().toISOString();
      console.log(`✅ Circuit breaker CLOSED: ${name}`);
    });

    // Request events
    breaker.on('success', (result) => {
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
      console.warn(`❌ Circuit breaker failure in ${name}:`, error.message);
    });

    breaker.on('timeout', () => {
      metrics.timeouts++;
      metrics.stats.totalFailures++;
      metrics.stats.totalRequests++;
      this.updateStats(metrics);
      console.warn(`⏰ Circuit breaker timeout in ${name}`);
    });

    breaker.on('fallback', (result) => {
      metrics.fallbacks++;
      console.log(`🔄 Circuit breaker fallback executed for ${name}`);
    });
  }

  /**
   * Update calculated statistics for metrics
   * @param {Object} metrics - Metrics object to update
   */
  updateStats(metrics) {
    const { totalRequests, totalFailures } = metrics.stats;
    metrics.stats.errorRate = totalRequests > 0 ? (totalFailures / totalRequests) * 100 : 0;
  }

  /**
   * Get circuit breaker by name
   * @param {string} name - Breaker name
   * @returns {CircuitBreaker|null} Circuit breaker instance or null
   */
  getBreaker(name) {
    return this.breakers.get(name) || null;
  }

  /**
   * Get metrics for a specific circuit breaker
   * @param {string} name - Breaker name
   * @returns {Object|null} Metrics object or null
   */
  getMetrics(name) {
    return this.metrics.get(name) || null;
  }

  /**
   * Get metrics for all circuit breakers
   * @returns {Object} Map of all metrics
   */
  getAllMetrics() {
    const allMetrics = {};
    for (const [name, metrics] of this.metrics) {
      allMetrics[name] = {
        ...metrics,
        // Include current circuit breaker state from the actual breaker
        currentState: this.breakers.get(name)?.opened ? 'OPEN' : 
                     this.breakers.get(name)?.halfOpen ? 'HALF_OPEN' : 'CLOSED'
      };
    }
    return allMetrics;
  }

  /**
   * Get summary statistics across all circuit breakers
   * @returns {Object} Summary statistics
   */
  getSummary() {
    const summary = {
      totalBreakers: this.breakers.size,
      openBreakers: 0,
      halfOpenBreakers: 0,
      closedBreakers: 0,
      totalRequests: 0,
      totalFailures: 0,
      overallErrorRate: 0
    };

    for (const [name, metrics] of this.metrics) {
      const breaker = this.breakers.get(name);
      
      if (breaker?.opened) summary.openBreakers++;
      else if (breaker?.halfOpen) summary.halfOpenBreakers++;
      else summary.closedBreakers++;

      summary.totalRequests += metrics.stats.totalRequests;
      summary.totalFailures += metrics.stats.totalFailures;
    }

    summary.overallErrorRate = summary.totalRequests > 0 ? 
      (summary.totalFailures / summary.totalRequests) * 100 : 0;

    return summary;
  }

  /**
   * Create a fallback function that returns cached data
   * @param {*} fallbackData - Data to return when circuit is open
   * @param {string} description - Description for logging
   * @returns {Function} Fallback function
   */
  createCacheFallback(fallbackData, description = 'cached data') {
    return () => {
      console.log(`🔄 Using fallback: ${description}`);
      return fallbackData;
    };
  }

  /**
   * Shutdown all circuit breakers and clear resources
   */
  shutdown() {
    for (const [name, breaker] of this.breakers) {
      try {
        breaker.shutdown();
        console.log(`🔧 Circuit breaker shutdown: ${name}`);
      } catch (error) {
        console.warn(`Failed to shutdown circuit breaker ${name}:`, error.message);
      }
    }
    this.breakers.clear();
    this.metrics.clear();
  }
}

// Export a singleton instance for use across the application
module.exports = new CircuitBreakerManager();