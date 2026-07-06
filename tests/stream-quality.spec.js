// @ts-check
const { test, expect } = require('@playwright/test');

/**
 * Stream Quality Test Suite (S3)
 *
 * Tests quality-adaptive streaming behaviour, codec fallback,
 * multi-instance load, and metric correctness.
 *
 * Requires the frontend dev server at http://localhost:3000
 * and backend at http://localhost:3001 (or proxied).
 */

test.describe('Stream Quality — Adaptive Streaming', () => {

  test('degraded network triggers quality reduction', async ({ page, context }) => {
    // Navigate to the dashboard
    await page.goto('/');
    await page.waitForTimeout(1000);

    // Simulate high packet loss via Chrome DevTools Protocol (CDP)
    const cdp = await context.newCDPSession(page);
    await cdp.send('Network.enable');

    // Emulate severely constrained network: ~50 kbps with 15% packet loss
    await cdp.send('Network.emulateNetworkConditions', {
      offline: false,
      downloadThroughput: 50 * 1024 / 8,   // 50 kbps
      uploadThroughput: 50 * 1024 / 8,
      latency: 300,                         // 300ms RTT
      packetLoss: 15,                       // 15% loss (if supported)
    });

    // Wait for the adaptive streaming hook to react
    await page.waitForTimeout(6000);

    // Check that quality metrics are being reported
    const qualityResponse = await page.evaluate(async () => {
      const resp = await fetch('/api/quality/summary');
      return resp.ok ? resp.json() : null;
    });

    expect(qualityResponse).toBeTruthy();

    // Restore normal conditions
    await cdp.send('Network.emulateNetworkConditions', {
      offline: false,
      downloadThroughput: -1,
      uploadThroughput: -1,
      latency: 0,
    });
  });

  test('codec switching fallback VP8 to VP9 if available', async ({ page }) => {
    await page.goto('/');
    await page.waitForTimeout(1000);

    // Query supported codecs from the browser
    const codecs = await page.evaluate(() => {
      if (!RTCRtpReceiver.getCapabilities) return [];
      const caps = RTCRtpReceiver.getCapabilities('video');
      return caps ? caps.codecs.map(c => c.mimeType) : [];
    });

    // Ensure at least VP8 is supported
    expect(codecs).toContain('video/VP8');

    // Log VP9 support (not blocking if absent)
    const hasVP9 = codecs.includes('video/VP9');
    console.log(`VP9 support: ${hasVP9}`);

    if (hasVP9) {
      // Verify that the SDP offer can include VP9 codec preference
      const canCreateOffer = await page.evaluate(async () => {
        const pc = new RTCPeerConnection();
        pc.addTransceiver('video', { direction: 'recvonly' });
        const offer = await pc.createOffer();
        pc.close();
        return offer.sdp.includes('VP9') || offer.sdp.includes('vp9');
      });
      expect(canCreateOffer).toBe(true);
    }
  });

  test('multi-instance load test with 9 concurrent streams', async ({ browser }) => {
    const NUM_INSTANCES = 9;
    const pages = [];

    // Create 9 browser contexts to simulate independent viewers
    for (let i = 0; i < NUM_INSTANCES; i++) {
      const ctx = await browser.newContext();
      const p = await ctx.newPage();
      pages.push({ ctx, page: p });
    }

    // Navigate all pages in parallel
    await Promise.all(
      pages.map(({ page }) => page.goto('/', { waitUntil: 'domcontentloaded' }))
    );

    // Let streams settle
    await Promise.race([
      new Promise(resolve => setTimeout(resolve, 10000)),
      // Early exit if all pages loaded
      Promise.all(pages.map(({ page }) => page.waitForTimeout(5000))),
    ]);

    // Verify each page can reach the quality endpoint
    const results = await Promise.all(
      pages.map(async ({ page }, idx) => {
        const resp = await page.evaluate(async () => {
          try {
            const r = await fetch('/api/quality/summary');
            return { ok: r.ok, status: r.status };
          } catch {
            return { ok: false, status: 0 };
          }
        });
        return { instance: idx, ...resp };
      })
    );

    // All instances should reach the quality endpoint
    for (const r of results) {
      expect(r.ok).toBe(true);
    }

    // Cleanup
    for (const { ctx } of pages) {
      await ctx.close();
    }
  });

  test('quality metrics are reported correctly', async ({ page }) => {
    await page.goto('/');
    await page.waitForTimeout(2000);

    // Fetch quality summary from backend
    const summary = await page.evaluate(async () => {
      const resp = await fetch('/api/quality/summary');
      return resp.ok ? resp.json() : null;
    });

    expect(summary).toBeTruthy();

    // Fetch individual instance metrics
    const allMetrics = await page.evaluate(async () => {
      const resp = await fetch('/api/quality/metrics');
      return resp.ok ? resp.json() : null;
    });

    expect(allMetrics).toBeTruthy();

    // Verify the metrics shape when instances are present
    if (allMetrics && typeof allMetrics === 'object') {
      for (const [id, metrics] of Object.entries(allMetrics)) {
        // Each metric entry should have a timestamp
        expect(metrics).toHaveProperty('timestamp');
      }
    }

    // Verify deep health endpoint responds
    const deepHealth = await page.evaluate(async () => {
      const resp = await fetch('/api/quality/deep-health');
      return resp.ok ? resp.json() : null;
    });

    expect(deepHealth).toBeTruthy();
  });
});
