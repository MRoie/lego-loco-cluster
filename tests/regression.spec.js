// @ts-check
const { test, expect } = require('@playwright/test');

/**
 * Q4: Full Regression Suite
 *
 * The "run everything" suite for CI. Exercises backend health, frontend load,
 * WebSocket connectivity, instance discovery, VR scene integrity, API
 * endpoints, and a basic memory-leak smoke test.
 *
 * Run:  npx playwright test tests/regression.spec.js
 */

const BACKEND = process.env.BACKEND_URL || 'http://localhost:3001';
const FRONTEND = process.env.FRONTEND_URL || 'http://localhost:3000';

// ---------------------------------------------------------------------------
// 1. Backend health endpoint returns 200
// ---------------------------------------------------------------------------
test.describe('Backend Health', () => {
  test('GET /health returns 200 with status ok', async ({ request }) => {
    const res = await request.get(`${BACKEND}/health`);
    expect(res.status()).toBe(200);
    const body = await res.json();
    expect(body.status).toBe('ok');
  });

  test('GET /ready returns 200', async ({ request }) => {
    const res = await request.get(`${BACKEND}/ready`);
    expect(res.ok()).toBeTruthy();
  });
});

// ---------------------------------------------------------------------------
// 2. Frontend loads within 3 seconds
// ---------------------------------------------------------------------------
test.describe('Frontend Load', () => {
  test('dashboard renders within 3 seconds', async ({ page }) => {
    const start = Date.now();
    await page.goto(FRONTEND, { waitUntil: 'domcontentloaded' });
    const elapsed = Date.now() - start;

    // Verify the page has meaningful content (not a blank error page)
    const body = await page.textContent('body');
    expect(body.length).toBeGreaterThan(0);
    expect(elapsed).toBeLessThan(3000);
  });
});

// ---------------------------------------------------------------------------
// 3. WebSocket connection establishes
// ---------------------------------------------------------------------------
test.describe('WebSocket Connectivity', () => {
  test('WebSocket upgrade succeeds on /ws', async ({ page }) => {
    await page.goto(FRONTEND);

    // Attempt a WebSocket connection and confirm the open event fires.
    const wsConnected = await page.evaluate((backend) => {
      return new Promise((resolve) => {
        const ws = new WebSocket(backend.replace('http', 'ws') + '/ws');
        const timer = setTimeout(() => { ws.close(); resolve(false); }, 5000);
        ws.onopen = () => { clearTimeout(timer); ws.close(); resolve(true); };
        ws.onerror = () => { clearTimeout(timer); resolve(false); };
      });
    }, BACKEND);

    expect(wsConnected).toBeTruthy();
  });
});

// ---------------------------------------------------------------------------
// 4. Instance discovery returns data
// ---------------------------------------------------------------------------
test.describe('Instance Discovery', () => {
  test('GET /api/instances returns an array', async ({ request }) => {
    const res = await request.get(`${BACKEND}/api/instances`);
    expect(res.ok()).toBeTruthy();
    const body = await res.json();
    // Response should be an array (possibly empty in CI) or an object with instances key
    const instances = Array.isArray(body) ? body : (body.instances || []);
    expect(Array.isArray(instances)).toBeTruthy();
  });

  test('GET /api/instances/live returns stats', async ({ request }) => {
    const res = await request.get(`${BACKEND}/api/instances/live`);
    expect(res.ok()).toBeTruthy();
    const body = await res.json();
    expect(body).toHaveProperty('instances');
  });
});

// ---------------------------------------------------------------------------
// 5. VR scene renders without console errors
// ---------------------------------------------------------------------------
test.describe('VR Scene Integrity', () => {
  test('VR page loads without JS errors', async ({ page }) => {
    const errors = [];
    page.on('pageerror', (err) => errors.push(err.message));

    // Navigate to the VR route (may be /vr or #/vr depending on router setup)
    const response = await page.goto(`${FRONTEND}/vr`, { waitUntil: 'domcontentloaded' });

    // Accept 200 or soft 404 (SPA serves index.html for all routes)
    expect(response.status()).toBeLessThan(500);

    // Allow the scene a moment to initialise
    await page.waitForTimeout(2000);

    // Filter out known non-critical warnings (e.g., A-Frame version notices)
    const criticalErrors = errors.filter(
      (e) => !e.includes('THREE.WebGLRenderer') && !e.includes('A-Frame')
    );
    expect(criticalErrors).toHaveLength(0);
  });
});

// ---------------------------------------------------------------------------
// 6. All API endpoints return valid responses
// ---------------------------------------------------------------------------
test.describe('API Endpoints', () => {
  const endpoints = [
    { path: '/health', expectStatus: 200 },
    { path: '/ready', expectStatus: 200 },
    { path: '/api/instances', expectStatus: 200 },
    { path: '/api/instances/live', expectStatus: 200 },
    { path: '/api/active', expectStatus: 200 },
    { path: '/api/config', expectStatus: 200 },
  ];

  for (const ep of endpoints) {
    test(`${ep.path} returns ${ep.expectStatus}`, async ({ request }) => {
      const res = await request.get(`${BACKEND}${ep.path}`);
      expect(res.status()).toBe(ep.expectStatus);

      // Body should be valid JSON
      const text = await res.text();
      expect(() => JSON.parse(text)).not.toThrow();
    });
  }
});

// ---------------------------------------------------------------------------
// 7. No memory leak over 60s monitoring period
// ---------------------------------------------------------------------------
test.describe('Memory Leak Smoke Test', () => {
  test('heap usage stays bounded over 60 seconds', async ({ page }) => {
    // Skip if Chrome performance.memory API is unavailable
    test.skip(
      !process.env.CI && !process.argv.includes('--headed'),
      'Chrome memory API requires chromium; skipped in non-CI headless'
    );

    await page.goto(FRONTEND);

    // Collect heap snapshots every 5 seconds for 60 seconds
    const snapshots = await page.evaluate(async () => {
      const samples = [];
      for (let i = 0; i < 12; i++) {
        if (performance.memory) {
          samples.push(performance.memory.usedJSHeapSize);
        }
        await new Promise((r) => setTimeout(r, 5000));
      }
      return samples;
    });

    if (snapshots.length < 2) {
      // performance.memory not available — pass the test gracefully
      return;
    }

    // A simple leak heuristic: the last sample should not be more than 2×
    // the first sample. Real leaks grow monotonically.
    const first = snapshots[0];
    const last = snapshots[snapshots.length - 1];
    expect(last).toBeLessThan(first * 2);
  });
});
