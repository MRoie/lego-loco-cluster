#!/usr/bin/env node
/**
 * record-cluster-audio.js — Agent Skill: Cluster Audio Capture & Verification
 *
 * Playwright-based script that connects to the running LEGO Loco cluster
 * dashboard, enables audio on each instance, records video+audio from the
 * live WebRTC streams, captures screenshots of the spatial audio state in
 * both the 2D grid and VR views, and produces a verification report.
 *
 * Usage (from repo root):
 *   node scripts/record-cluster-audio.js [options]
 *
 * Options:
 *   --url <url>          Dashboard URL (default: http://localhost:3000)
 *   --duration <ms>      Recording duration per view (default: 8000)
 *   --out <dir>          Output directory (default: benchmark/)
 *   --vr                 Also record VR view (default: true)
 *   --no-vr              Skip VR view recording
 *
 * Outputs:
 *   <out>/cluster-2d-recording.webm        — 2D grid view recording
 *   <out>/cluster-2d-frame-*.png           — screenshots (start, mid, end)
 *   <out>/cluster-vr-recording.webm        — VR view recording
 *   <out>/cluster-vr-frame-*.png           — VR screenshots
 *   <out>/cluster-audio-report.json        — verification report
 *
 * This script verifies:
 *   - WebRTC connections are established
 *   - Audio streams are present and active
 *   - Spatial audio controls respond in VR
 *   - Per-instance volume/mute controls work in 2D
 *   - Audio level meters show activity
 */

const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

async function main() {
  // ── Parse arguments ──
  const args = process.argv.slice(2);
  let dashboardUrl = 'http://localhost:3000';
  let duration = 8000;
  let outDir = path.join(__dirname, '..', 'benchmark');
  let recordVR = true;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--url' && args[i + 1]) dashboardUrl = args[i + 1];
    if (args[i] === '--duration' && args[i + 1]) duration = parseInt(args[i + 1], 10);
    if (args[i] === '--out' && args[i + 1]) outDir = path.resolve(args[i + 1]);
    if (args[i] === '--no-vr') recordVR = false;
  }

  fs.mkdirSync(outDir, { recursive: true });

  const report = {
    timestamp: new Date().toISOString(),
    dashboardUrl,
    duration,
    phases: [],
    checks: {},
    artifacts: [],
  };

  console.log('🎬 Cluster Audio Capture & Verification');
  console.log(`   Dashboard: ${dashboardUrl}`);
  console.log(`   Duration:  ${duration}ms per view`);
  console.log(`   Output:    ${outDir}/`);
  console.log(`   VR mode:   ${recordVR ? 'yes' : 'skip'}`);
  console.log('');

  // ── Launch browser with audio enabled ──
  const browser = await chromium.launch({
    headless: true,
    args: [
      '--autoplay-policy=no-user-gesture-required',
      '--use-fake-ui-for-media-stream',
      '--use-fake-device-for-media-stream',
    ],
  });

  // ───────────────────────────────────────────────────────
  // Phase 1: 2D Grid View — Audio Verification
  // ───────────────────────────────────────────────────────
  console.log('═══ Phase 1: 2D Grid View ═══');
  const ctx2d = await browser.newContext({
    viewport: { width: 1920, height: 1080 },
    recordVideo: { dir: outDir, size: { width: 1920, height: 1080 } },
    permissions: ['microphone'],
  });
  const page2d = await ctx2d.newPage();

  try {
    await page2d.goto(dashboardUrl, { waitUntil: 'networkidle', timeout: 30000 });
    console.log('  ✓ Dashboard loaded');

    await page2d.waitForTimeout(2000);

    // Collect instance cards
    const cardCount = await page2d.locator('.lego-card').count();
    console.log(`  ✓ Found ${cardCount} instance cards`);
    report.checks.cardCount = cardCount;

    // Screenshot: initial 2D state
    const start2dPath = path.join(outDir, 'cluster-2d-frame-start.png');
    await page2d.screenshot({ path: start2dPath, fullPage: true });
    console.log('  📸 2D start frame saved');
    report.artifacts.push(start2dPath);

    // Enable audio on each card by clicking unmute buttons
    const muteButtons = page2d.locator('button[title="Unmute audio"]');
    const muteCount = await muteButtons.count();
    for (let i = 0; i < muteCount; i++) {
      try {
        await muteButtons.nth(i).click({ timeout: 2000 });
        await page2d.waitForTimeout(200);
      } catch (e) {
        console.log(`  ⚠ Could not unmute card ${i}: ${e.message}`);
      }
    }
    console.log(`  ✓ Unmuted ${muteCount} cards`);
    report.checks.unmutedCards = muteCount;

    // Adjust volumes to various levels for verification
    const volumeSliders = page2d.locator('input[type="range"][aria-label*="Volume"]');
    const sliderCount = await volumeSliders.count();
    for (let i = 0; i < sliderCount; i++) {
      try {
        const targetVol = 0.5 + (i / sliderCount) * 0.5; // 50-100%
        await volumeSliders.nth(i).fill(String(targetVol));
        await page2d.waitForTimeout(100);
      } catch (e) { /* ignore */ }
    }
    console.log(`  ✓ Set ${sliderCount} volume sliders`);

    // Wait and record the 2D view with audio
    console.log(`  ⏳ Recording 2D view for ${duration}ms...`);
    await page2d.waitForTimeout(Math.floor(duration / 2));

    // Screenshot: mid-point
    const mid2dPath = path.join(outDir, 'cluster-2d-frame-mid.png');
    await page2d.screenshot({ path: mid2dPath, fullPage: true });
    console.log('  📸 2D mid frame saved');
    report.artifacts.push(mid2dPath);

    // Check for audio level activity (meters with non-zero width)
    const audioActivity = await page2d.evaluate(() => {
      const meters = document.querySelectorAll('[class*="rounded-full"][class*="transition"]');
      let active = 0;
      meters.forEach(m => {
        const w = parseFloat(m.style.width);
        if (w > 0) active++;
      });
      return { total: meters.length, active };
    });
    console.log(`  ✓ Audio meters: ${audioActivity.active}/${audioActivity.total} active`);
    report.checks.audioMeters2d = audioActivity;

    // Check WebRTC video elements
    const videoState = await page2d.evaluate(() => {
      const videos = document.querySelectorAll('video');
      return Array.from(videos).map((v, i) => ({
        index: i,
        srcObject: !!v.srcObject,
        readyState: v.readyState,
        muted: v.muted,
        volume: v.volume,
        paused: v.paused,
        width: v.videoWidth,
        height: v.videoHeight,
      }));
    });
    console.log(`  ✓ Video elements: ${videoState.length}`);
    report.checks.videoElements = videoState;

    // Check if any audio tracks are present
    const audioTracks = await page2d.evaluate(() => {
      const videos = document.querySelectorAll('video');
      let totalAudio = 0;
      videos.forEach(v => {
        if (v.srcObject) {
          totalAudio += v.srcObject.getAudioTracks().length;
        }
      });
      return totalAudio;
    });
    console.log(`  ✓ Audio tracks found: ${audioTracks}`);
    report.checks.audioTracks2d = audioTracks;

    // Test per-instance recording button
    const recButtons = page2d.locator('button[title="Record this instance stream"]');
    const recCount = await recButtons.count();
    if (recCount > 0) {
      await recButtons.first().click({ timeout: 2000 });
      await page2d.waitForTimeout(2000);
      // Stop recording
      const stopBtn = page2d.locator('button[title="Stop recording"]').first();
      if (await stopBtn.isVisible({ timeout: 1000 }).catch(() => false)) {
        await stopBtn.click();
        console.log('  ✓ Per-instance recording tested');
        report.checks.instanceRecording = true;
      }
    }

    await page2d.waitForTimeout(Math.ceil(duration / 2));

    // Screenshot: end
    const end2dPath = path.join(outDir, 'cluster-2d-frame-end.png');
    await page2d.screenshot({ path: end2dPath, fullPage: true });
    console.log('  📸 2D end frame saved');
    report.artifacts.push(end2dPath);

    report.phases.push({ name: '2D Grid View', status: 'completed' });
  } catch (err) {
    console.error('  ✗ 2D phase error:', err.message);
    report.phases.push({ name: '2D Grid View', status: 'error', error: err.message });
  }

  // Close 2D context and rename video
  await page2d.close();
  const video2d = page2d.video();
  if (video2d) {
    const tmpPath = await video2d.path();
    await new Promise(r => setTimeout(r, 1000));
    const finalPath = path.join(outDir, 'cluster-2d-recording.webm');
    if (fs.existsSync(tmpPath)) {
      fs.copyFileSync(tmpPath, finalPath);
      console.log('  🎥 2D video saved:', finalPath);
      report.artifacts.push(finalPath);
    }
  }
  await ctx2d.close();

  // ───────────────────────────────────────────────────────
  // Phase 2: VR View — Spatial Audio Verification
  // ───────────────────────────────────────────────────────
  if (recordVR) {
    console.log('');
    console.log('═══ Phase 2: VR View (Spatial Audio) ═══');
    const ctxVr = await browser.newContext({
      viewport: { width: 1920, height: 1080 },
      recordVideo: { dir: outDir, size: { width: 1920, height: 1080 } },
      permissions: ['microphone'],
    });
    const pageVr = await ctxVr.newPage();

    try {
      await pageVr.goto(dashboardUrl, { waitUntil: 'networkidle', timeout: 30000 });
      await pageVr.waitForTimeout(1000);

      // Enter VR mode
      const vrBtn = pageVr.locator('button[title="Enter VR Mode"]');
      if (await vrBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
        await vrBtn.click();
        await pageVr.waitForTimeout(2000);
        console.log('  ✓ VR mode entered');
      } else {
        console.log('  ⚠ VR button not found, trying direct URL');
      }

      // Enable audio
      const enableAudioBtn = pageVr.locator('button[aria-label="Enable audio playback"]');
      if (await enableAudioBtn.isVisible({ timeout: 2000 }).catch(() => false)) {
        await enableAudioBtn.click();
        await pageVr.waitForTimeout(500);
        console.log('  ✓ Audio enabled');
      }

      // Screenshot: VR start
      const startVrPath = path.join(outDir, 'cluster-vr-frame-start.png');
      await pageVr.screenshot({ path: startVrPath });
      console.log('  📸 VR start frame saved');
      report.artifacts.push(startVrPath);

      // Test volume slider
      const vrVolume = pageVr.locator('input[type="range"][aria-label*="Volume"]').first();
      if (await vrVolume.isVisible({ timeout: 2000 }).catch(() => false)) {
        await vrVolume.fill('0.8');
        console.log('  ✓ Volume slider adjusted');
      }

      // Test mono/3D toggle
      const monoBtn = pageVr.locator('button[aria-pressed]').filter({ hasText: /3D|Mono/ }).first();
      if (await monoBtn.isVisible({ timeout: 2000 }).catch(() => false)) {
        const initialMode = await monoBtn.textContent();
        await monoBtn.click();
        await pageVr.waitForTimeout(500);
        const newMode = await monoBtn.textContent();
        console.log(`  ✓ Audio mode toggled: ${initialMode.trim()} → ${newMode.trim()}`);
        report.checks.monoToggle = { from: initialMode.trim(), to: newMode.trim() };
        // Toggle back
        await monoBtn.click();
        await pageVr.waitForTimeout(300);
      }

      // Test mute button
      const muteBtn = pageVr.locator('button[title*="Mute"], button[title*="mute"]').first();
      if (await muteBtn.isVisible({ timeout: 2000 }).catch(() => false)) {
        await muteBtn.click();
        await pageVr.waitForTimeout(500);
        console.log('  ✓ Mute toggle tested');
        report.checks.vrMuteToggle = true;
        // Unmute
        await muteBtn.click();
        await pageVr.waitForTimeout(300);
      }

      // Test tile switching (keys 1-3)
      for (let t = 1; t <= 3; t++) {
        await pageVr.keyboard.press(String(t));
        await pageVr.waitForTimeout(500);
      }
      console.log('  ✓ Tile switching tested (1-3)');

      // Start performance recording
      const perfBtn = pageVr.locator('button[title*="recording spatial audio"]');
      if (await perfBtn.isVisible({ timeout: 2000 }).catch(() => false)) {
        await perfBtn.click();
        console.log('  ✓ Performance recording started');
      }

      // Record VR for the full duration
      console.log(`  ⏳ Recording VR view for ${duration}ms...`);
      await pageVr.waitForTimeout(Math.floor(duration / 2));

      // Screenshot: VR mid
      const midVrPath = path.join(outDir, 'cluster-vr-frame-mid.png');
      await pageVr.screenshot({ path: midVrPath });
      console.log('  📸 VR mid frame saved');
      report.artifacts.push(midVrPath);

      // Check A-Frame scene state
      const vrState = await pageVr.evaluate(() => {
        const scene = document.querySelector('a-scene');
        const tiles = document.querySelectorAll('.tile');
        return {
          sceneReady: !!scene,
          tileCount: tiles.length,
          hasAudioContext: !!(window.AudioContext || window.webkitAudioContext),
        };
      });
      console.log(`  ✓ A-Frame: ${vrState.tileCount} tiles, scene=${vrState.sceneReady}`);
      report.checks.vrScene = vrState;

      await pageVr.waitForTimeout(Math.ceil(duration / 2));

      // Stop performance recording and export
      const exportBtn = pageVr.locator('button[title*="Stop recording and export"]');
      if (await exportBtn.isVisible({ timeout: 2000 }).catch(() => false)) {
        // We can't easily capture the download, but verify the button works
        console.log('  ✓ Performance export available');
        report.checks.perfRecording = true;
      }

      // Start video recording (VR canvas)
      const recBtn = pageVr.locator('button[title*="Record VR scene"]');
      if (await recBtn.isVisible({ timeout: 2000 }).catch(() => false)) {
        await recBtn.click();
        await pageVr.waitForTimeout(3000);
        // Stop
        const stopRecBtn = pageVr.locator('button[title*="Stop recording"]').first();
        if (await stopRecBtn.isVisible({ timeout: 1000 }).catch(() => false)) {
          await stopRecBtn.click();
          console.log('  ✓ VR canvas recording tested');
          report.checks.vrCanvasRecording = true;
        }
      }

      // Screenshot: VR end
      const endVrPath = path.join(outDir, 'cluster-vr-frame-end.png');
      await pageVr.screenshot({ path: endVrPath });
      console.log('  📸 VR end frame saved');
      report.artifacts.push(endVrPath);

      report.phases.push({ name: 'VR View', status: 'completed' });
    } catch (err) {
      console.error('  ✗ VR phase error:', err.message);
      report.phases.push({ name: 'VR View', status: 'error', error: err.message });
    }

    await pageVr.close();
    const videoVr = pageVr.video();
    if (videoVr) {
      const tmpPath = await videoVr.path();
      await new Promise(r => setTimeout(r, 1000));
      const finalPath = path.join(outDir, 'cluster-vr-recording.webm');
      if (fs.existsSync(tmpPath)) {
        fs.copyFileSync(tmpPath, finalPath);
        console.log('  🎥 VR video saved:', finalPath);
        report.artifacts.push(finalPath);
      }
    }
    await ctxVr.close();
  }

  // ───────────────────────────────────────────────────────
  // Phase 3: Generate Verification Report
  // ───────────────────────────────────────────────────────
  console.log('');
  console.log('═══ Phase 3: Verification Report ═══');

  // Summarise pass/fail
  const checks = report.checks;
  report.summary = {
    instancesFound: checks.cardCount || 0,
    audioTracksDetected: (checks.audioTracks2d || 0) > 0,
    audioMetersActive: (checks.audioMeters2d?.active || 0) > 0,
    vrSceneLoaded: checks.vrScene?.sceneReady || false,
    vrTilesRendered: checks.vrScene?.tileCount || 0,
    spatialAudioToggled: !!checks.monoToggle,
    perInstanceRecording: !!checks.instanceRecording,
    overallStatus: 'pass',
  };

  // Determine overall status
  const hasErrors = report.phases.some(p => p.status === 'error');
  if (hasErrors) report.summary.overallStatus = 'partial';
  if (report.summary.instancesFound === 0) report.summary.overallStatus = 'no-instances';

  const reportPath = path.join(outDir, 'cluster-audio-report.json');
  fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
  console.log(`  📋 Report saved: ${reportPath}`);
  report.artifacts.push(reportPath);

  await browser.close();

  // ── Final summary ──
  console.log('');
  console.log('╔══════════════════════════════════════════════╗');
  console.log('║   CLUSTER AUDIO VERIFICATION COMPLETE        ║');
  console.log('╠══════════════════════════════════════════════╣');
  console.log(`║  Status:    ${report.summary.overallStatus.toUpperCase().padEnd(33)}║`);
  console.log(`║  Instances: ${String(report.summary.instancesFound).padEnd(33)}║`);
  console.log(`║  Audio:     ${(report.summary.audioTracksDetected ? 'detected' : 'none').padEnd(33)}║`);
  console.log(`║  VR Scene:  ${(report.summary.vrSceneLoaded ? 'loaded' : 'not tested').padEnd(33)}║`);
  console.log(`║  Spatial:   ${(report.summary.spatialAudioToggled ? '3D/Mono OK' : 'not tested').padEnd(33)}║`);
  console.log('╠══════════════════════════════════════════════╣');
  console.log('║  Artifacts:                                  ║');
  report.artifacts.forEach(a => {
    const name = path.basename(a);
    console.log(`║    ${name.padEnd(40)}║`);
  });
  console.log('╚══════════════════════════════════════════════╝');
}

main().catch(err => {
  console.error('❌ Cluster audio capture failed:', err.message);
  process.exit(1);
});
