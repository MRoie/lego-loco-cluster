#!/usr/bin/env node
/**
 * record-spatial-audio.js — Agent Skill: Headless Spatial Audio Recorder
 *
 * Playwright-based script that opens the spatial audio visualizer in a
 * headless Chromium browser, records it for a configurable duration, and
 * saves screenshots plus a WebM video to the benchmark/ directory.
 *
 * Usage (from repo root):
 *   node scripts/record-spatial-audio.js [--duration 5000] [--out benchmark/]
 *
 * Outputs:
 *   <out>/spatial-audio-recording.webm   — screen capture video
 *   <out>/spatial-audio-frame-start.png  — first-frame screenshot
 *   <out>/spatial-audio-frame-mid.png    — mid-point screenshot
 *   <out>/spatial-audio-frame-end.png    — final-frame screenshot
 *
 * This script is designed to be invoked by CI agents, Codex agents, or
 * developers to produce visual artifacts of the spatial audio system
 * running live for PR review and benchmarking.
 */

const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

async function main() {
  // ── Parse arguments ──
  const args = process.argv.slice(2);
  let duration = 5000;
  let outDir = path.join(__dirname, '..', 'benchmark');

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--duration' && args[i + 1]) duration = parseInt(args[i + 1], 10);
    if (args[i] === '--out' && args[i + 1]) outDir = path.resolve(args[i + 1]);
  }

  fs.mkdirSync(outDir, { recursive: true });

  const visualizerPath = path.join(__dirname, '..', 'benchmark', 'spatial-audio-visualizer.html');
  if (!fs.existsSync(visualizerPath)) {
    console.error('❌ Visualizer not found at', visualizerPath);
    process.exit(1);
  }

  const fileUrl = `file://${visualizerPath}`;
  console.log('🎬 Spatial Audio Recorder — Agent Skill');
  console.log(`   Visualizer: ${fileUrl}`);
  console.log(`   Duration:   ${duration}ms`);
  console.log(`   Output:     ${outDir}/`);
  console.log('');

  // ── Launch browser ──
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 1280, height: 720 },
    recordVideo: {
      dir: outDir,
      size: { width: 1280, height: 720 },
    },
  });

  const page = await context.newPage();
  await page.goto(fileUrl, { waitUntil: 'domcontentloaded' });

  // Wait for the animation to initialise
  await page.waitForTimeout(500);

  // ── Screenshot: start frame ──
  const startPath = path.join(outDir, 'spatial-audio-frame-start.png');
  await page.screenshot({ path: startPath });
  console.log('📸 Start frame saved:', startPath);

  // ── Let the visualizer play for half the duration ──
  await page.waitForTimeout(Math.floor(duration / 2));

  // ── Screenshot: mid-point frame ──
  const midPath = path.join(outDir, 'spatial-audio-frame-mid.png');
  await page.screenshot({ path: midPath });
  console.log('📸 Mid frame saved:', midPath);

  // ── Let the visualizer play for the remaining duration ──
  await page.waitForTimeout(Math.ceil(duration / 2));

  // ── Screenshot: end frame ──
  const endPath = path.join(outDir, 'spatial-audio-frame-end.png');
  await page.screenshot({ path: endPath });
  console.log('📸 End frame saved:', endPath);

  // ── Close page to finalise video ──
  await page.close();

  // Playwright saves the video with an auto-generated name; rename it
  const video = page.video();
  if (video) {
    const tmpPath = await video.path();
    const finalPath = path.join(outDir, 'spatial-audio-recording.webm');
    // Wait for the file to be fully written
    await new Promise((r) => setTimeout(r, 1000));
    if (fs.existsSync(tmpPath)) {
      fs.copyFileSync(tmpPath, finalPath);
      console.log('🎥 Video saved:', finalPath);
    }
  }

  await context.close();
  await browser.close();

  console.log('');
  console.log('✅ Recording complete. Artifacts:');
  console.log(`   ${path.join(outDir, 'spatial-audio-frame-start.png')}`);
  console.log(`   ${path.join(outDir, 'spatial-audio-frame-mid.png')}`);
  console.log(`   ${path.join(outDir, 'spatial-audio-frame-end.png')}`);
  console.log(`   ${path.join(outDir, 'spatial-audio-recording.webm')}`);
}

main().catch((err) => {
  console.error('❌ Recording failed:', err.message);
  process.exit(1);
});
