/**
 * Frontend Metrics Collector
 * Prometheus-style metrics collection for the frontend.
 * Always active.
 */

class MetricsCollector {
    constructor() {
        this.counters = new Map();
        this.gauges = new Map();
        this.histograms = new Map();
        this.reportingInterval = null;
    }

    incrementCounter(name, labels = {}) {
        const key = this._makeKey(name, labels);
        this.counters.set(key, (this.counters.get(key) || 0) + 1);
    }

    setGauge(name, value, labels = {}) {
        const key = this._makeKey(name, labels);
        this.gauges.set(key, value);
    }

    recordHistogram(name, value, labels = {}) {
        const key = this._makeKey(name, labels);
        if (!this.histograms.has(key)) {
            this.histograms.set(key, []);
        }
        this.histograms.get(key).push({ value, timestamp: Date.now() });
    }

    _makeKey(name, labels) {
        const labelStr = Object.entries(labels)
            .sort(([a], [b]) => a.localeCompare(b))
            .map(([k, v]) => `${k}="${v}"`)
            .join(',');
        return labelStr ? `${name}{${labelStr}}` : name;
    }

    getAll() {
        return {
            counters: Object.fromEntries(this.counters),
            gauges: Object.fromEntries(this.gauges),
            histograms: Object.fromEntries(
                Array.from(this.histograms.entries()).map(([k, v]) => [
                    k,
                    this._calculateHistogramStats(v)
                ])
            )
        };
    }

    _calculateHistogramStats(values) {
        if (!values || values.length === 0) return null;

        const sorted = values.map(v => v.value).sort((a, b) => a - b);
        const sum = sorted.reduce((acc, val) => acc + val, 0);

        return {
            count: values.length,
            sum: sum,
            avg: sum / values.length,
            min: sorted[0],
            max: sorted[sorted.length - 1],
            p50: this._percentile(sorted, 0.5),
            p95: this._percentile(sorted, 0.95),
            p99: this._percentile(sorted, 0.99),
        };
    }

    _percentile(sortedValues, p) {
        if (sortedValues.length === 0) return 0;
        const idx = Math.floor((sortedValues.length - 1) * p);
        return sortedValues[idx];
    }

    // Auto-report to backend every 30s
    startReporting(intervalMs = 30000) {
        if (this.reportingInterval) clearInterval(this.reportingInterval);

        this.reportingInterval = setInterval(() => {
            const metricsData = this.getAll();

            // Only send if there's data
            if (Object.keys(metricsData.counters).length === 0 &&
                Object.keys(metricsData.gauges).length === 0 &&
                Object.keys(metricsData.histograms).length === 0) {
                return;
            }

            // We use navigator.sendBeacon for reliability on page unload, 
            // but fetch for regular updates to handle responses
            fetch('/api/metrics/frontend', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(metricsData)
            }).catch(err => {
                // Silent fail for metrics reporting to avoid console noise
                // But we could log to our internal logger if we had circular dependency resolution
                console.warn('[Metrics] Failed to report metrics:', err);
            });

            // Optional: Clear histograms after reporting to avoid unbounded growth?
            // For now, we keep them to show session-long stats, but in a real app 
            // we might want to window them.
            // this.histograms.clear(); 
        }, intervalMs);
    }

    stopReporting() {
        if (this.reportingInterval) {
            clearInterval(this.reportingInterval);
            this.reportingInterval = null;
        }
    }
}

export const metrics = new MetricsCollector();
