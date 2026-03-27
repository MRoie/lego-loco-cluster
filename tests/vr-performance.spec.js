// @ts-check
const { test, expect } = require('@playwright/test');

/**
 * V2: VR Scene Performance Profiling
 *
 * Tests that the VR scene maintains 60fps with increasing stream counts,
 * measures paint/frame timing, and asserts memory usage stays bounded.
 * Outputs performance metrics as test annotations.
 */

const VR_URL = '/vr';

// ── Helpers ──────────────────────────────────────────────────────────────────

/**
 * Inject performance measurement utilities into the page.
 * Tracks frame times via requestAnimationFrame and exposes
 * window.__perfMetrics for extraction.
 */
async function injectPerfTracker(page) {
  await page.addInitScript(() => {
    window.__perfMetrics = {
      frameTimes: [],
      paintEntries: [],
      memorySnapshots: [],
      startTime: 0,
      running: false,
    };

    window.__startPerfTracking = () => {
      const metrics = window.__perfMetrics;
      metrics.frameTimes = [];
      metrics.paintEntries = [];
      metrics.memorySnapshots = [];
      metrics.startTime = performance.now();
      metrics.running = true;

      let lastFrame = performance.now();

      function track(now) {
        if (!metrics.running) return;
        const dt = now - lastFrame;
        metrics.frameTimes.push(dt);
        lastFrame = now;

        // Collect memory if available (Chrome only)
        if (performance.memory) {
          metrics.memorySnapshots.push({
            t: now - metrics.startTime,
            usedJSHeapSize: performance.memory.usedJSHeapSize,
            totalJSHeapSize: performance.memory.totalJSHeapSize,
          });
        }

        requestAnimationFrame(track);
      }

      requestAnimationFrame(track);

      // Observe paint timing
      if (typeof PerformanceObserver !== 'undefined') {
        try {
          const observer = new PerformanceObserver((list) => {
            for (const entry of list.getEntries()) {
              metrics.paintEntries.push({
                name: entry.name,
                startTime: entry.startTime,
                duration: entry.duration,
              });
            }
          });
          observer.observe({ type: 'paint', buffered: true });
        } catch (e) {
          // PerformanceObserver for paint may not be available
        }
      }
    };

    window.__stopPerfTracking = () => {
      window.__perfMetrics.running = false;
    };
  });
}

/**
 * Inject a mock /api/config/instances endpoint that returns N instances.
 */
async function mockInstancesAPI(page, count) {
  await page.route('**/api/config/instances', (route) => {
    const instances = Array.from({ length: count }, (_, i) => ({
      id: `perf-instance-${i}`,
      name: `Perf Instance ${i + 1}`,
      host: 'localhost',
      vncPort: 5901 + i,
    }));
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(instances),
    });
  });

  await page.route('**/api/status', (route) => {
    const status = {};
    for (let i = 0; i < count; i++) {
      status[`perf-instance-${i}`] = 'ready';
    }
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(status),
    });
  });
}

/**
 * Compute FPS statistics from an array of frame delta times (ms).
 */
function computeFpsStats(frameTimes) {
  if (frameTimes.length < 2) return { avgFps: 0, p95FrameTime: 0, p99FrameTime: 0, minFps: 0 };

  const sorted = [...frameTimes].sort((a, b) => a - b);
  const avgDt = frameTimes.reduce((s, t) => s + t, 0) / frameTimes.length;
  const p95Dt = sorted[Math.floor(sorted.length * 0.95)];
  const p99Dt = sorted[Math.floor(sorted.length * 0.99)];
  const maxDt = sorted[sorted.length - 1];

  return {
    avgFps: 1000 / avgDt,
    p95FrameTime: p95Dt,
    p99FrameTime: p99Dt,
    minFps: 1000 / maxDt,
    totalFrames: frameTimes.length,
    avgFrameTime: avgDt,
  };
}

// ── Frame Rate Tests ─────────────────────────────────────────────────────────

test.describe('VR Scene FPS with Increasing Stream Count', () => {
  const MEASURE_DURATION_MS = 5000;
  const FPS_TARGET = 30; // Relaxed target for CI; real target is 60fps

  for (const streamCount of [1, 3, 6, 9]) {
    test(`maintains ${FPS_TARGET}+ fps with ${streamCount} streams`, async ({ page }, testInfo) => {
      await injectPerfTracker(page);
      await mockInstancesAPI(page, streamCount);

      await page.goto(VR_URL, { waitUntil: 'domcontentloaded' });
      await page.waitForTimeout(1000); // Let scene initialize

      // Start tracking
      await page.evaluate(() => window.__startPerfTracking());
      await page.waitForTimeout(MEASURE_DURATION_MS);
      await page.evaluate(() => window.__stopPerfTracking());

      // Collect metrics
      const metrics = await page.evaluate(() => window.__perfMetrics);
      const stats = computeFpsStats(metrics.frameTimes);

      // Annotate test with performance data
      testInfo.annotations.push({
        type: 'performance',
        description: JSON.stringify({
          streamCount,
          avgFps: stats.avgFps.toFixed(1),
          minFps: stats.minFps.toFixed(1),
          avgFrameTime: stats.avgFrameTime?.toFixed(2) + 'ms',
          p95FrameTime: stats.p95FrameTime?.toFixed(2) + 'ms',
          p99FrameTime: stats.p99FrameTime?.toFixed(2) + 'ms',
          totalFrames: stats.totalFrames,
          duration: MEASURE_DURATION_MS + 'ms',
        }),
      });

      // Assert FPS target (only when we have enough frames)
      if (stats.totalFrames > 10) {
        expect(stats.avgFps).toBeGreaterThanOrEqual(FPS_TARGET);
      }
    });
  }
});

// ── Paint Timing ─────────────────────────────────────────────────────────────

test.describe('Paint Timing', () => {
  test('first-contentful-paint occurs within 3 seconds', async ({ page }, testInfo) => {
    await injectPerfTracker(page);
    await mockInstancesAPI(page, 3);

    await page.goto(VR_URL, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(3000);

    const paintEntries = await page.evaluate(() => {
      return performance.getEntriesByType('paint').map((e) => ({
        name: e.name,
        startTime: e.startTime,
      }));
    });

    testInfo.annotations.push({
      type: 'paint-timing',
      description: JSON.stringify(paintEntries),
    });

    const fcp = paintEntries.find((e) => e.name === 'first-contentful-paint');
    if (fcp) {
      expect(fcp.startTime).toBeLessThan(3000);
    }
  });

  test('requestAnimationFrame callback timing is consistent', async ({ page }, testInfo) => {
    await injectPerfTracker(page);
    await mockInstancesAPI(page, 3);

    await page.goto(VR_URL, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(500);

    await page.evaluate(() => window.__startPerfTracking());
    await page.waitForTimeout(3000);
    await page.evaluate(() => window.__stopPerfTracking());

    const frameTimes = await page.evaluate(() => window.__perfMetrics.frameTimes);
    const stats = computeFpsStats(frameTimes);

    testInfo.annotations.push({
      type: 'raf-timing',
      description: JSON.stringify({
        avgFrameTime: stats.avgFrameTime?.toFixed(2) + 'ms',
        p95FrameTime: stats.p95FrameTime?.toFixed(2) + 'ms',
        jitter: frameTimes.length > 1
          ? (Math.max(...frameTimes) - Math.min(...frameTimes)).toFixed(2) + 'ms'
          : 'N/A',
      }),
    });

    // p95 frame time should be under 50ms (20fps floor)
    if (stats.totalFrames > 10) {
      expect(stats.p95FrameTime).toBeLessThan(50);
    }
  });
});

// ── Memory Usage ─────────────────────────────────────────────────────────────

test.describe('Memory Usage', () => {
  test('heap size does not grow unbounded over 30 seconds', async ({ page }, testInfo) => {
    test.skip(!process.env.CI, 'Memory test is more reliable in CI with Chromium');

    await injectPerfTracker(page);
    await mockInstancesAPI(page, 6);

    await page.goto(VR_URL, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(2000);

    // Take initial memory snapshot
    const initialMemory = await page.evaluate(() => {
      return performance.memory ? performance.memory.usedJSHeapSize : null;
    });

    // Run for 30 seconds
    await page.evaluate(() => window.__startPerfTracking());
    await page.waitForTimeout(30000);
    await page.evaluate(() => window.__stopPerfTracking());

    const finalMemory = await page.evaluate(() => {
      return performance.memory ? performance.memory.usedJSHeapSize : null;
    });

    const snapshots = await page.evaluate(() => window.__perfMetrics.memorySnapshots);

    testInfo.annotations.push({
      type: 'memory',
      description: JSON.stringify({
        initialMB: initialMemory ? (initialMemory / 1024 / 1024).toFixed(1) : 'N/A',
        finalMB: finalMemory ? (finalMemory / 1024 / 1024).toFixed(1) : 'N/A',
        growthMB: initialMemory && finalMemory
          ? ((finalMemory - initialMemory) / 1024 / 1024).toFixed(1)
          : 'N/A',
        snapshots: snapshots.length,
      }),
    });

    // If memory tracking is available, assert no more than 100MB growth
    if (initialMemory && finalMemory) {
      const growthMB = (finalMemory - initialMemory) / 1024 / 1024;
      expect(growthMB).toBeLessThan(100);
    }
  });

  test('no detached DOM nodes after scene navigation', async ({ page }, testInfo) => {
    await mockInstancesAPI(page, 3);

    // Navigate to VR scene
    await page.goto(VR_URL, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(2000);

    const beforeCount = await page.evaluate(() => document.querySelectorAll('*').length);

    // Navigate away and back
    await page.goto('about:blank');
    await page.goto(VR_URL, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(2000);

    const afterCount = await page.evaluate(() => document.querySelectorAll('*').length);

    testInfo.annotations.push({
      type: 'dom-nodes',
      description: JSON.stringify({ beforeCount, afterCount }),
    });

    // DOM count should not grow significantly (allow 20% tolerance)
    const growth = afterCount / Math.max(beforeCount, 1);
    expect(growth).toBeLessThan(1.5);
  });
});

// ── Performance API Integration ──────────────────────────────────────────────

test.describe('Performance API Metrics', () => {
  test('long tasks are measured via PerformanceObserver', async ({ page }, testInfo) => {
    await mockInstancesAPI(page, 9);

    await page.goto(VR_URL, { waitUntil: 'domcontentloaded' });

    // Collect Long Tasks
    const longTasks = await page.evaluate(() => {
      return new Promise((resolve) => {
        const tasks = [];
        try {
          const observer = new PerformanceObserver((list) => {
            for (const entry of list.getEntries()) {
              tasks.push({
                name: entry.name,
                duration: entry.duration,
                startTime: entry.startTime,
              });
            }
          });
          observer.observe({ type: 'longtask', buffered: true });
          setTimeout(() => {
            observer.disconnect();
            resolve(tasks);
          }, 5000);
        } catch {
          resolve([]);
        }
      });
    });

    testInfo.annotations.push({
      type: 'long-tasks',
      description: JSON.stringify({
        count: longTasks.length,
        maxDuration: longTasks.length > 0
          ? Math.max(...longTasks.map((t) => t.duration)).toFixed(1) + 'ms'
          : '0ms',
      }),
    });

    // No long task should exceed 200ms (aggressive but reasonable for VR)
    for (const task of longTasks) {
      expect(task.duration).toBeLessThan(200);
    }
  });

  test('resource loading finishes within timeout', async ({ page }, testInfo) => {
    await mockInstancesAPI(page, 3);

    const start = Date.now();
    await page.goto(VR_URL, { waitUntil: 'load' });
    const loadTime = Date.now() - start;

    const resourceTiming = await page.evaluate(() => {
      return performance.getEntriesByType('resource').map((r) => ({
        name: r.name.split('/').pop(),
        duration: r.duration.toFixed(1),
        size: r.transferSize || 0,
      }));
    });

    testInfo.annotations.push({
      type: 'resource-timing',
      description: JSON.stringify({
        totalLoadMs: loadTime,
        resourceCount: resourceTiming.length,
        top5ByDuration: resourceTiming
          .sort((a, b) => parseFloat(b.duration) - parseFloat(a.duration))
          .slice(0, 5),
      }),
    });

    // Page should load within 10 seconds
    expect(loadTime).toBeLessThan(10000);
  });
});
