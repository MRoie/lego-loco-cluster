#!/usr/bin/env node
/**
 * record-fullscreen-instance.js
 *
 * Playwright script that connects to the LEGO Loco cluster dashboard,
 * waits for WebRTC video+audio to establish, then uses the browser's
 * MediaRecorder API to capture the actual WebRTC stream (video+audio)
 * as a WebM file. Also takes screenshots.
 *
 * Unlike Playwright's built-in recordVideo (screen-only, no audio),
 * this captures the real WebRTC MediaStream including Opus audio.
 *
 * Usage:
 *   node scripts/record-fullscreen-instance.js [options]
 *
 * Options:
 *   --url <url>        Dashboard URL (default: http://localhost:3000)
 *   --duration <ms>    Recording duration (default: 30000)
 *   --out <dir>        Output directory (default: benchmark/fullscreen-recording)
 */

const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

async function main() {
  const args = process.argv.slice(2);
  let dashboardUrl = 'http://localhost:3000';
  let duration = 30000;
  let outDir = path.join(__dirname, '..', 'benchmark', 'fullscreen-recording');

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--url' && args[i + 1]) dashboardUrl = args[i + 1];
    if (args[i] === '--duration' && args[i + 1]) duration = parseInt(args[i + 1], 10);
    if (args[i] === '--out' && args[i + 1]) outDir = path.resolve(args[i + 1]);
  }

  fs.mkdirSync(outDir, { recursive: true });

  console.log(`🎬 Fullscreen Instance Recording (WebRTC Stream Capture)`);
  console.log(`   Dashboard: ${dashboardUrl}`);
  console.log(`   Duration:  ${duration}ms`);
  console.log(`   Output:    ${outDir}`);
  console.log('');

  const browser = await chromium.launch({
    headless: true,
    args: [
      '--autoplay-policy=no-user-gesture-required',
      '--use-fake-ui-for-media-stream',
      '--disable-web-security',
      '--allow-running-insecure-content',
    ],
  });

  const context = await browser.newContext({
    viewport: { width: 1280, height: 960 },
    permissions: ['microphone', 'camera'],
    // Also do a screen recording as a visual backup
    recordVideo: {
      dir: outDir,
      size: { width: 1280, height: 960 },
    },
  });

  const page = await context.newPage();

  // Suppress console noise
  page.on('console', () => {});
  page.on('pageerror', () => {});

  try {
    // ── Step 1: Load dashboard ──
    console.log('═══ Step 1: Load Dashboard ═══');
    await page.goto(dashboardUrl, { waitUntil: 'networkidle', timeout: 30000 });
    console.log('  ✓ Dashboard loaded');
    await page.waitForTimeout(3000);

    // ── Step 2: Wait for instance cards ──
    console.log('═══ Step 2: Find Instance Cards ═══');
    const cards = page.locator('.lego-card');
    const cardCount = await cards.count();
    console.log(`  ✓ Found ${cardCount} instance cards`);

    if (cardCount === 0) {
      console.log('  ✗ No instance cards found - nothing to record');
      await browser.close();
      return;
    }

    // ── Step 3: Unmute audio ──
    console.log('═══ Step 3: Enable Audio ═══');
    const unmuteBtn = page.locator('button[title="Unmute audio"]').first();
    if (await unmuteBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
      await unmuteBtn.click();
      console.log('  ✓ Audio unmuted');
    } else {
      console.log('  ⚠ No unmute button found (audio may already be on)');
    }

    // Set volume to 100%
    const volumeSlider = page.locator('input[type="range"]').first();
    if (await volumeSlider.isVisible({ timeout: 2000 }).catch(() => false)) {
      await volumeSlider.fill('1');
      console.log('  ✓ Volume set to 100%');
    }

    // ── Step 4: Wait for WebRTC video element ──
    console.log('═══ Step 4: Wait for WebRTC Stream ═══');
    let videoReady = false;
    for (let attempt = 0; attempt < 20; attempt++) {
      const videoInfo = await page.evaluate(() => {
        const videos = document.querySelectorAll('video');
        if (videos.length === 0) return null;
        const v = videos[0];
        return {
          srcObject: !!v.srcObject,
          readyState: v.readyState,
          videoWidth: v.videoWidth,
          videoHeight: v.videoHeight,
          audioTracks: v.srcObject ? v.srcObject.getAudioTracks().length : 0,
          videoTracks: v.srcObject ? v.srcObject.getVideoTracks().length : 0,
        };
      });

      if (videoInfo && videoInfo.srcObject && videoInfo.videoTracks > 0) {
        console.log(`  ✓ WebRTC connected after ${attempt + 1}s`);
        console.log(`    Video: ${videoInfo.videoWidth}x${videoInfo.videoHeight}, readyState=${videoInfo.readyState}`);
        console.log(`    Tracks: ${videoInfo.videoTracks} video, ${videoInfo.audioTracks} audio`);
        videoReady = true;
        break;
      }
      if (attempt % 5 === 0) {
        console.log(`  ⏳ Waiting for WebRTC... (${attempt}s, video=${videoInfo ? 'found' : 'none'})`);
      }
      await page.waitForTimeout(1000);
    }

    if (!videoReady) {
      console.log('  ⚠ WebRTC video not fully ready, proceeding anyway');
    }

    // ── Step 5: Take "before" screenshot ──
    await page.screenshot({ path: path.join(outDir, 'instance-before.png'), fullPage: false });
    console.log('  📸 Before screenshot saved');

    // ── Step 6: Start MediaRecorder capture of the WebRTC stream ──
    console.log(`═══ Step 5: Recording WebRTC Stream (${duration / 1000}s) ═══`);

    // Inject MediaRecorder logic into the page to capture the actual stream
    const recordingHandle = await page.evaluateHandle(async (durationMs) => {
      return new Promise((resolve) => {
        const videos = document.querySelectorAll('video');
        if (videos.length === 0) {
          resolve({ error: 'No video elements found' });
          return;
        }

        const video = videos[0];
        const stream = video.srcObject;
        if (!stream) {
          resolve({ error: 'No srcObject on video' });
          return;
        }

        // Create a canvas-based capture that combines video rendering + audio
        const canvas = document.createElement('canvas');
        canvas.width = video.videoWidth || 1024;
        canvas.height = video.videoHeight || 768;
        const ctx = canvas.getContext('2d');

        // Capture canvas at video frame rate
        const canvasStream = canvas.captureStream(25);

        // Add audio tracks from the WebRTC stream to the canvas stream
        stream.getAudioTracks().forEach(track => {
          canvasStream.addTrack(track);
        });

        // Draw video frames to canvas
        let drawInterval;
        const drawFrame = () => {
          if (video.readyState >= 2) {
            // Update canvas size if video dimensions change
            if (video.videoWidth > 0 && video.videoHeight > 0) {
              canvas.width = video.videoWidth;
              canvas.height = video.videoHeight;
            }
            ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
          }
        };
        drawInterval = setInterval(drawFrame, 40); // 25fps

        // Try different MIME types for MediaRecorder
        const mimeTypes = [
          'video/webm;codecs=vp9,opus',
          'video/webm;codecs=vp8,opus',
          'video/webm;codecs=vp9',
          'video/webm;codecs=vp8',
          'video/webm',
        ];

        let selectedMime = '';
        for (const mime of mimeTypes) {
          if (MediaRecorder.isTypeSupported(mime)) {
            selectedMime = mime;
            break;
          }
        }

        if (!selectedMime) {
          clearInterval(drawInterval);
          resolve({ error: 'No supported MIME type for MediaRecorder' });
          return;
        }

        const chunks = [];
        const recorder = new MediaRecorder(canvasStream, {
          mimeType: selectedMime,
          videoBitsPerSecond: 2500000,
          audioBitsPerSecond: 128000,
        });

        recorder.ondataavailable = (e) => {
          if (e.data && e.data.size > 0) {
            chunks.push(e.data);
          }
        };

        recorder.onstop = async () => {
          clearInterval(drawInterval);
          const blob = new Blob(chunks, { type: selectedMime });
          // Convert blob to base64 for transfer back to Node
          const reader = new FileReader();
          reader.onloadend = () => {
            resolve({
              data: reader.result.split(',')[1], // base64 data
              mimeType: selectedMime,
              size: blob.size,
              chunks: chunks.length,
              canvasSize: `${canvas.width}x${canvas.height}`,
              audioTracks: stream.getAudioTracks().length,
              videoTracks: stream.getVideoTracks().length,
            });
          };
          reader.readAsDataURL(blob);
        };

        recorder.onerror = (e) => {
          clearInterval(drawInterval);
          resolve({ error: `MediaRecorder error: ${e.error?.message || 'unknown'}` });
        };

        // Start recording with 1-second timeslices
        recorder.start(1000);

        // Also store reference for status checks
        window.__legoRecorder = recorder;
        window.__legoRecordingInfo = {
          mime: selectedMime,
          startTime: Date.now(),
          audioTracks: stream.getAudioTracks().length,
          videoTracks: stream.getVideoTracks().length,
        };

        // Stop after duration
        setTimeout(() => {
          if (recorder.state === 'recording') {
            recorder.stop();
          }
        }, durationMs);
      });
    }, duration);

    // Wait for recording to complete + take periodic screenshots
    const screenshotTimes = [
      { pct: 0.25, name: 'quarter' },
      { pct: 0.5, name: 'mid' },
      { pct: 0.75, name: 'threequarter' },
    ];

    for (const st of screenshotTimes) {
      await page.waitForTimeout(duration * st.pct / screenshotTimes.length);
      await page.screenshot({ path: path.join(outDir, `instance-${st.name}.png`) });
      console.log(`  📸 ${st.name} screenshot saved`);

      // Check recording status
      const status = await page.evaluate(() => {
        const info = window.__legoRecordingInfo;
        const recorder = window.__legoRecorder;
        return {
          state: recorder?.state,
          elapsed: info ? Date.now() - info.startTime : 0,
          mime: info?.mime,
          audioTracks: info?.audioTracks,
          videoTracks: info?.videoTracks,
        };
      });
      console.log(`  ⏺ Recording: state=${status.state}, elapsed=${Math.round(status.elapsed / 1000)}s, ` +
        `audio=${status.audioTracks}, video=${status.videoTracks}`);
    }

    // Wait for the rest of the recording
    const alreadyWaited = screenshotTimes.reduce((sum, st) => sum + duration * st.pct / screenshotTimes.length, 0);
    const remaining = duration - alreadyWaited + 2000; // +2s buffer for MediaRecorder finalization
    if (remaining > 0) {
      console.log(`  ⏳ Waiting ${Math.round(remaining / 1000)}s for recording to finish...`);
      await page.waitForTimeout(remaining);
    }

    // ── Step 7: Retrieve the recorded data ──
    console.log('═══ Step 6: Saving Recording ═══');
    const result = await recordingHandle.jsonValue();

    if (result.error) {
      console.log(`  ✗ Recording failed: ${result.error}`);
    } else {
      // Save the WebM file from base64
      const videoBuffer = Buffer.from(result.data, 'base64');
      const videoPath = path.join(outDir, 'instance-stream-recording.webm');
      fs.writeFileSync(videoPath, videoBuffer);
      console.log(`  🎥 Stream recording saved: ${videoPath}`);
      console.log(`     Size: ${(videoBuffer.length / 1024 / 1024).toFixed(2)} MB`);
      console.log(`     MIME: ${result.mimeType}`);
      console.log(`     Canvas: ${result.canvasSize}`);
      console.log(`     Chunks: ${result.chunks}`);
      console.log(`     Audio tracks in stream: ${result.audioTracks}`);
      console.log(`     Video tracks in stream: ${result.videoTracks}`);
    }

    // Take final screenshot
    await page.screenshot({ path: path.join(outDir, 'instance-after.png') });
    console.log('  📸 After screenshot saved');

    // ── Step 7: System stats ──
    console.log('═══ Step 7: System Stats ═══');
    try {
      const { execSync } = require('child_process');
      const statsCmd = process.platform === 'win32'
        ? 'powershell -Command "Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 Name,CPU,WorkingSet | Format-Table -AutoSize"'
        : 'ps aux --sort=-%cpu | head -6';
      const stats = execSync(statsCmd, { timeout: 10000 }).toString();
      console.log(stats);
    } catch (e) {
      console.log('  ⚠ Could not collect system stats');
    }

    // ── Summary ──
    const report = {
      timestamp: new Date().toISOString(),
      dashboard: dashboardUrl,
      duration: duration,
      recording: result.error ? { error: result.error } : {
        file: 'instance-stream-recording.webm',
        sizeBytes: result.data ? Buffer.from(result.data, 'base64').length : 0,
        mimeType: result.mimeType,
        canvasSize: result.canvasSize,
        audioTracks: result.audioTracks,
        videoTracks: result.videoTracks,
        chunks: result.chunks,
      },
      screenshots: [
        'instance-before.png',
        'instance-quarter.png',
        'instance-mid.png',
        'instance-threequarter.png',
        'instance-after.png',
      ],
    };

    fs.writeFileSync(path.join(outDir, 'recording-report.json'), JSON.stringify(report, null, 2));
    console.log('');
    console.log('╔══════════════════════════════════════════════════╗');
    console.log('║   FULLSCREEN INSTANCE RECORDING COMPLETE         ║');
    console.log('╠══════════════════════════════════════════════════╣');
    console.log(`║  Duration: ${duration / 1000}s                              ║`);
    console.log(`║  Audio:    ${result.audioTracks || 0} tracks                        ║`);
    console.log(`║  Video:    ${result.videoTracks || 0} tracks                        ║`);
    console.log(`║  Size:     ${result.data ? (Buffer.from(result.data, 'base64').length / 1024 / 1024).toFixed(1) : '0'} MB                           ║`);
    console.log('╚══════════════════════════════════════════════════╝');

  } catch (err) {
    console.error(`Error: ${err.message}`);
    await page.screenshot({ path: path.join(outDir, 'error-screenshot.png') }).catch(() => {});
  } finally {
    await context.close();
    await browser.close();
  }
}

main().catch(console.error);
