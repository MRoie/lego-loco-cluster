#!/usr/bin/env node
/**
 * record-progressive-loading.js — capture the dashboard's progressive
 * loading experience (AppLoadingOverlay -> instance grid) as video evidence.
 *
 * Recording starts BEFORE navigation so the overlay phase is fully captured,
 * and the browser runs with a throttled network profile so the two loading
 * phases are visible rather than instantaneous.
 *
 * Usage:
 *   node scripts/record-progressive-loading.js [--url http://localhost:3000]
 *     [--out proof/] [--duration 15000] [--latency 150]
 *
 * Outputs in --out:
 *   progressive-loading.webm            screen recording
 *   progressive-loading-overlay.png     overlay phase screenshot
 *   progressive-loading-loaded.png      loaded dashboard screenshot
 */

const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

async function main() {
  const args = process.argv.slice(2);
  let url = 'http://localhost:3000';
  let outDir = path.join(__dirname, '..', 'proof');
  let duration = 15000;
  let latency = 150;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--url' && args[i + 1]) url = args[i + 1];
    if (args[i] === '--out' && args[i + 1]) outDir = path.resolve(args[i + 1]);
    if (args[i] === '--duration' && args[i + 1]) duration = parseInt(args[i + 1], 10);
    if (args[i] === '--latency' && args[i + 1]) latency = parseInt(args[i + 1], 10);
  }

  fs.mkdirSync(outDir, { recursive: true });

  console.log(`🎬 Recording progressive loading from ${url}`);
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 1280, height: 800 },
    recordVideo: { dir: outDir, size: { width: 1280, height: 800 } },
  });

  const page = await context.newPage();

  // Throttle API responses so both loading phases are observable
  const cdp = await context.newCDPSession(page);
  await cdp.send('Network.emulateNetworkConditions', {
    offline: false,
    latency,
    downloadThroughput: 1.5 * 1024 * 1024 / 8,
    uploadThroughput: 750 * 1024 / 8,
  });

  await page.goto(url, { waitUntil: 'domcontentloaded' });

  // Overlay phase screenshot (best effort — it may already be dismissing)
  try {
    await page.waitForSelector('text=Cluster Dashboard', { timeout: 4000 });
    await page.screenshot({ path: path.join(outDir, 'progressive-loading-overlay.png') });
    console.log('📸 Overlay phase captured');
  } catch (e) {
    console.log('ℹ️  Overlay dismissed before capture (fast network)');
  }

  // Wait for the grid to be interactive, then capture the loaded state
  await page.waitForTimeout(duration);
  await page.screenshot({ path: path.join(outDir, 'progressive-loading-loaded.png') });
  console.log('📸 Loaded dashboard captured');

  await context.close(); // flushes the video
  await browser.close();

  // Rename playwright's random video filename to something stable
  const vids = fs.readdirSync(outDir).filter((f) => f.endsWith('.webm') && f !== 'progressive-loading.webm');
  if (vids.length > 0) {
    const newest = vids
      .map((f) => ({ f, t: fs.statSync(path.join(outDir, f)).mtimeMs }))
      .sort((a, b) => b.t - a.t)[0].f;
    fs.copyFileSync(path.join(outDir, newest), path.join(outDir, 'progressive-loading.webm'));
    fs.unlinkSync(path.join(outDir, newest));
  }

  console.log('✅ Artifacts:');
  console.log(`   ${path.join(outDir, 'progressive-loading.webm')}`);
  console.log(`   ${path.join(outDir, 'progressive-loading-loaded.png')}`);
}

main().catch((err) => {
  console.error('❌ Recording failed:', err.message);
  process.exit(1);
});
