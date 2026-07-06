/**
 * Observability Utilities Unit Tests
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createLogger } from './logger';
import { metrics } from './metrics';
import { RetryStrategy } from './retry';

// Mock console methods
const consoleSpy = {
    log: vi.spyOn(console, 'log').mockImplementation(() => { }),
    warn: vi.spyOn(console, 'warn').mockImplementation(() => { }),
    error: vi.spyOn(console, 'error').mockImplementation(() => { }),
};

describe('FrontendLogger', () => {
    beforeEach(() => {
        vi.clearAllMocks();
    });

    it('should log info messages with correct format', () => {
        const logger = createLogger('TestComponent');
        logger.info('test message', { key: 'value' });

        expect(consoleSpy.log).toHaveBeenCalled();
        const lastCall = consoleSpy.log.mock.calls[0];

        // Check format: [TIMESTAMP] [INFO] [TestComponent]:
        expect(lastCall[0]).toMatch(/\[INFO\] \[TestComponent\]:/);
        expect(lastCall[2]).toBe('test message');
        expect(lastCall[3]).toEqual({ key: 'value' });
    });

    it('should dispatch custom event on log', () => {
        const dispatchSpy = vi.spyOn(window, 'dispatchEvent');
        const logger = createLogger('TestComponent');
        logger.info('event test');

        expect(dispatchSpy).toHaveBeenCalled();
        const event = dispatchSpy.mock.calls[0][0];
        expect(event.type).toBe('frontendLog');
        expect(event.detail.message).toBe('event test');
        expect(event.detail.level).toBe('info');
    });
});

describe('MetricsCollector', () => {
    beforeEach(() => {
        // Reset metrics
        metrics.counters = new Map();
        metrics.gauges = new Map();
        metrics.histograms = new Map();
    });

    it('should increment counters', () => {
        metrics.incrementCounter('test_counter', { label: 'a' });
        metrics.incrementCounter('test_counter', { label: 'a' });

        const data = metrics.getAll();
        expect(data.counters['test_counter{label="a"}']).toBe(2);
    });

    it('should set gauges', () => {
        metrics.setGauge('test_gauge', 42, { label: 'b' });

        const data = metrics.getAll();
        expect(data.gauges['test_gauge{label="b"}']).toBe(42);
    });

    it('should record histograms and calculate stats', () => {
        metrics.recordHistogram('test_hist', 10);
        metrics.recordHistogram('test_hist', 20);
        metrics.recordHistogram('test_hist', 30);

        const data = metrics.getAll();
        const stats = data.histograms['test_hist'];

        expect(stats.count).toBe(3);
        expect(stats.sum).toBe(60);
        expect(stats.avg).toBe(20);
        expect(stats.min).toBe(10);
        expect(stats.max).toBe(30);
        expect(stats.p50).toBe(20);
    });
});

describe('RetryStrategy', () => {
    it('should retry on failure up to max attempts', async () => {
        const strategy = new RetryStrategy(3, 10, 100); // Fast retries for test
        const mockFn = vi.fn()
            .mockRejectedValueOnce(new Error('Fail 1'))
            .mockRejectedValueOnce(new Error('Fail 2'))
            .mockResolvedValue('Success');

        const result = await strategy.execute(mockFn);

        expect(result).toBe('Success');
        expect(mockFn).toHaveBeenCalledTimes(3);
    });

    it('should throw after max attempts exceeded', async () => {
        const strategy = new RetryStrategy(2, 10, 100);
        const mockFn = vi.fn().mockRejectedValue(new Error('Always fail'));

        await expect(strategy.execute(mockFn)).rejects.toThrow('Max retry attempts (2) exceeded');
        expect(mockFn).toHaveBeenCalledTimes(2);
    });
});
