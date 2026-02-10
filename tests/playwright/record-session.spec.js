// @ts-check
const { test, expect } = require('@playwright/test');

/**
 * Lego Loco Cluster — Full Demo Session Recorder
 * 
 * Records a video of the web dashboard showing:
 * - 3×3 grid of all 9 emulator instances
 * - Live benchmark overlay with real-time metrics
 * - Instance interactions (click, focus)
 * - LAN status and connectivity
 * 
 * Usage:
 *   npx playwright test tests/playwright/record-session.spec.js --headed
 * 
 * The video is saved to tests/playwright/videos/
 */

test.describe('Lego Loco Cluster Demo Recording', () => {

  test.use({
    video: { mode: 'on', size: { width: 1920, height: 1080 } },
    viewport: { width: 1920, height: 1080 },
    launchOptions: { slowMo: 200 },
  });

  test('Record full 3x3 grid with live benchmarks', async ({ page, context }) => {
    // Navigate to the dashboard
    await page.goto('/', { waitUntil: 'networkidle', timeout: 30000 });

    // Wait for instances to load
    await page.waitForTimeout(5000);

    // Verify the benchmark overlay is visible
    const benchOverlay = page.locator('text=LIVE BENCHMARK');
    await expect(benchOverlay).toBeVisible({ timeout: 15000 });

    // Take initial screenshot
    await page.screenshot({ path: 'tests/playwright/screenshots/grid-initial.png', fullPage: true });

    // Wait for instances to appear in the grid
    await page.waitForTimeout(3000);

    // Count visible instance cards
    const cards = page.locator('[class*="lego-card"]');
    const cardCount = await cards.count();
    console.log(`Visible instance cards: ${cardCount}`);

    // Click through each instance card to show focus transitions
    for (let i = 0; i < Math.min(cardCount, 9); i++) {
      const card = cards.nth(i);
      if (await card.isVisible()) {
        await card.click();
        await page.waitForTimeout(1500);
      }
    }

    // Screenshot the grid with an active card
    await page.screenshot({ path: 'tests/playwright/screenshots/grid-focused.png', fullPage: true });

    // Wait to capture benchmark data accumulating
    console.log('Recording benchmark overlay for 30 seconds...');
    await page.waitForTimeout(30000);

    // Check benchmark overlay metrics
    const benchContent = await page.locator('.font-mono').allTextContents();
    console.log('Benchmark overlay content:', benchContent.slice(0, 5).join(' | '));

    // Screenshot final state
    await page.screenshot({ path: 'tests/playwright/screenshots/grid-final.png', fullPage: true });

    // Continue recording for another 30 seconds to show stability
    console.log('Recording stability period for 30 seconds...');
    await page.waitForTimeout(30000);

    // Final screenshot
    await page.screenshot({ path: 'tests/playwright/screenshots/session-complete.png', fullPage: true });
    console.log('Recording complete. Video saved automatically.');
  });

  test('Record LAN status and connectivity', async ({ page }) => {
    await page.goto('/', { waitUntil: 'networkidle', timeout: 30000 });
    await page.waitForTimeout(5000);

    // Fetch and log LAN status
    const lanStatus = await page.evaluate(async () => {
      const res = await fetch('/api/lan-status');
      return res.json();
    });
    console.log('LAN Status:', JSON.stringify(lanStatus, null, 2));

    // Fetch and log benchmark metrics
    const benchMetrics = await page.evaluate(async () => {
      const res = await fetch('/api/benchmark/live');
      return res.json();
    });
    console.log('Benchmark Metrics:', JSON.stringify(benchMetrics.summary, null, 2));

    // Record for 20 seconds showing the dashboard
    await page.waitForTimeout(20000);

    await page.screenshot({ path: 'tests/playwright/screenshots/lan-status.png', fullPage: true });
  });

  test('Record instance interaction demo', async ({ page }) => {
    await page.goto('/', { waitUntil: 'networkidle', timeout: 30000 });
    await page.waitForTimeout(5000);

    // Click each instance in sequence with pauses
    const cards = page.locator('[class*="lego-card"]');
    const count = await cards.count();

    for (let i = 0; i < count; i++) {
      const card = cards.nth(i);
      if (await card.isVisible()) {
        // Hover effect
        await card.hover();
        await page.waitForTimeout(800);
        // Click
        await card.click();
        await page.waitForTimeout(2000);
      }
    }

    // Record final panoramic view
    await page.waitForTimeout(10000);
    await page.screenshot({ path: 'tests/playwright/screenshots/interaction-demo.png', fullPage: true });
  });
});
