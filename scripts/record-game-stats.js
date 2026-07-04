#!/usr/bin/env node
/**
 * Record game opening + system stats for a single Lego Loco instance.
 * 
 * Captures:
 *  - Browser video of the VNC/dashboard view (Playwright)
 *  - Periodic system stats (CPU, RAM, GPU, Docker)
 *  - Screenshots at key moments
 *  - Final JSON report
 * 
 * Usage:
 *   node scripts/record-game-stats.js [--url URL] [--duration SECONDS] [--out DIR]
 */

const { chromium } = require('playwright');
const { execSync, exec } = require('child_process');
const fs = require('fs');
const path = require('path');

// ---- CLI args ----
const args = process.argv.slice(2);
function getArg(name, fallback) {
  const i = args.indexOf(`--${name}`);
  return i >= 0 && args[i + 1] ? args[i + 1] : fallback;
}
const DASHBOARD_URL = getArg('url', 'http://localhost:3000');
const DURATION_SEC = parseInt(getArg('duration', '60'), 10);
const OUT_DIR = getArg('out', path.join(__dirname, '..', 'benchmark', 'recordings'));

// ---- System stats collection ----
function getSystemStats() {
  const stats = { timestamp: new Date().toISOString() };

  try {
    // CPU usage via PowerShell
    const cpu = execSync(
      'powershell -NoProfile -Command "Get-CimInstance Win32_Processor | Select-Object -ExpandProperty LoadPercentage"',
      { timeout: 5000, encoding: 'utf-8' }
    ).trim();
    stats.cpuPercent = parseInt(cpu, 10) || 0;
  } catch { stats.cpuPercent = -1; }

  try {
    // Memory via PowerShell
    const mem = execSync(
      'powershell -NoProfile -Command "$os=Get-CimInstance Win32_OperatingSystem; \\"$($os.TotalVisibleMemorySize),$($os.FreePhysicalMemory)\\""',
      { timeout: 5000, encoding: 'utf-8' }
    ).trim();
    const [total, free] = mem.split(',').map(Number);
    stats.memTotalMB = Math.round(total / 1024);
    stats.memUsedMB = Math.round((total - free) / 1024);
    stats.memPercent = Math.round(((total - free) / total) * 100);
  } catch { stats.memTotalMB = -1; stats.memUsedMB = -1; stats.memPercent = -1; }

  try {
    // GPU usage via nvidia-smi (if available)
    const gpu = execSync(
      'nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits',
      { timeout: 5000, encoding: 'utf-8' }
    ).trim().split('\n')[0];
    const [gpuUtil, gpuMemUsed, gpuMemTotal] = gpu.split(',').map(s => parseInt(s.trim(), 10));
    stats.gpuPercent = gpuUtil;
    stats.gpuMemUsedMB = gpuMemUsed;
    stats.gpuMemTotalMB = gpuMemTotal;
  } catch { stats.gpuPercent = -1; }

  try {
    // Docker stats for emulator container
    const docker = execSync(
      'docker stats --no-stream --format "{{.Name}},{{.CPUPerc}},{{.MemUsage}}" 2>/dev/null | head -20',
      { timeout: 10000, encoding: 'utf-8' }
    ).trim();
    stats.dockerContainers = docker.split('\n').filter(Boolean).map(line => {
      const [name, cpu, mem] = line.split(',');
      return { name, cpu, mem };
    });
  } catch { stats.dockerContainers = []; }

  try {
    // Kind node resource usage
    const kubectl = execSync(
      'kubectl top nodes 2>/dev/null',
      { timeout: 10000, encoding: 'utf-8' }
    ).trim();
    stats.k8sNodes = kubectl;
  } catch { stats.k8sNodes = 'unavailable'; }

  try {
    // Pod resource usage
    const pods = execSync(
      'kubectl top pods -n loco 2>/dev/null',
      { timeout: 10000, encoding: 'utf-8' }
    ).trim();
    stats.k8sPods = pods;
  } catch { stats.k8sPods = 'unavailable'; }

  return stats;
}

// ---- Main recording function ----
async function main() {
  console.log('=== Lego Loco Game Recording + System Stats ===');
  console.log(`Dashboard: ${DASHBOARD_URL}`);
  console.log(`Duration:  ${DURATION_SEC}s`);
  console.log(`Output:    ${OUT_DIR}`);
  console.log('');

  // Create output directory
  fs.mkdirSync(OUT_DIR, { recursive: true });
  const runId = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);

  // Collect initial system stats
  console.log('[1/6] Collecting baseline system stats...');
  const baselineStats = getSystemStats();
  console.log(`  CPU: ${baselineStats.cpuPercent}% | RAM: ${baselineStats.memUsedMB}/${baselineStats.memTotalMB}MB (${baselineStats.memPercent}%)`);
  if (baselineStats.gpuPercent >= 0) console.log(`  GPU: ${baselineStats.gpuPercent}% | VRAM: ${baselineStats.gpuMemUsedMB}/${baselineStats.gpuMemTotalMB}MB`);

  // Launch browser with video recording
  console.log('[2/6] Launching browser with video recording...');
  const browser = await chromium.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-web-security', '--autoplay-policy=no-user-gesture-required'],
  });
  const context = await browser.newContext({
    viewport: { width: 1920, height: 1080 },
    recordVideo: {
      dir: OUT_DIR,
      size: { width: 1920, height: 1080 },
    },
    ignoreHTTPSErrors: true,
  });
  const page = await context.newPage();

  // Navigate to dashboard
  console.log('[3/6] Loading dashboard...');
  await page.goto(DASHBOARD_URL, { waitUntil: 'networkidle', timeout: 30000 }).catch(() => {
    console.log('  Warning: networkidle timeout, continuing...');
  });
  await page.waitForTimeout(3000); // Let React hydrate

  // Take initial screenshot
  const screenshotInit = path.join(OUT_DIR, `${runId}-01-dashboard-loaded.png`);
  await page.screenshot({ path: screenshotInit, fullPage: true });
  console.log(`  Screenshot: ${screenshotInit}`);

  // Collect stats during recording
  console.log(`[4/6] Recording for ${DURATION_SEC}s with periodic stats...`);
  const statsSamples = [baselineStats];
  const SAMPLE_INTERVAL = 5; // seconds
  const totalSamples = Math.floor(DURATION_SEC / SAMPLE_INTERVAL);
  const screenshots = [screenshotInit];

  for (let i = 0; i < totalSamples; i++) {
    await page.waitForTimeout(SAMPLE_INTERVAL * 1000);
    const elapsed = (i + 1) * SAMPLE_INTERVAL;
    const sample = getSystemStats();
    statsSamples.push(sample);
    console.log(`  [${elapsed}s] CPU: ${sample.cpuPercent}% | RAM: ${sample.memPercent}%${sample.gpuPercent >= 0 ? ` | GPU: ${sample.gpuPercent}%` : ''}`);

    // Capture screenshots at specific milestones
    if (elapsed === 10 || elapsed === 30 || elapsed === DURATION_SEC) {
      const ssPath = path.join(OUT_DIR, `${runId}-at-${elapsed}s.png`);
      await page.screenshot({ path: ssPath, fullPage: true });
      screenshots.push(ssPath);
    }
  }

  // Final screenshot
  const screenshotFinal = path.join(OUT_DIR, `${runId}-final.png`);
  await page.screenshot({ path: screenshotFinal, fullPage: true });
  screenshots.push(screenshotFinal);

  // Check instance status via API
  console.log('[5/6] Querying instance status...');
  let instanceData = [];
  try {
    const resp = await page.evaluate(async (url) => {
      const r = await fetch(`${url}/api/instances`);
      return r.json();
    }, DASHBOARD_URL.replace(':3000', ':3001'));
    instanceData = resp;
    console.log(`  ${instanceData.length} instances discovered`);
    instanceData.forEach(inst => {
      console.log(`    ${inst.id}: ${inst.status} (${inst.name || 'unnamed'})`);
    });
  } catch (e) {
    console.log(`  API query failed: ${e.message}`);
    // Try direct curl
    try {
      const apiResp = execSync('curl -s http://localhost:3001/api/instances', { timeout: 5000, encoding: 'utf-8' });
      instanceData = JSON.parse(apiResp);
    } catch { /* ignore */ }
  }

  // Close browser (saves video)
  console.log('[6/6] Saving recordings...');
  const video = page.video();
  await context.close();
  await browser.close();

  // Rename video file
  if (video) {
    const videoPath = await video.path();
    const destVideo = path.join(OUT_DIR, `${runId}-game-recording.webm`);
    try {
      fs.renameSync(videoPath, destVideo);
      console.log(`  Video: ${destVideo}`);
    } catch {
      console.log(`  Video saved at: ${videoPath}`);
    }
  }

  // Generate report
  const report = {
    runId,
    url: DASHBOARD_URL,
    duration: DURATION_SEC,
    startTime: statsSamples[0].timestamp,
    endTime: statsSamples[statsSamples.length - 1].timestamp,
    instances: instanceData.length,
    instanceDetails: instanceData.map(i => ({ id: i.id, status: i.status, name: i.name })),
    stats: {
      samples: statsSamples.length,
      avgCpu: Math.round(statsSamples.reduce((a, s) => a + Math.max(0, s.cpuPercent), 0) / statsSamples.length),
      maxCpu: Math.max(...statsSamples.map(s => s.cpuPercent)),
      avgMemPercent: Math.round(statsSamples.reduce((a, s) => a + Math.max(0, s.memPercent), 0) / statsSamples.length),
      maxMemMB: Math.max(...statsSamples.map(s => s.memUsedMB || 0)),
      avgGpu: statsSamples[0].gpuPercent >= 0
        ? Math.round(statsSamples.reduce((a, s) => a + Math.max(0, s.gpuPercent), 0) / statsSamples.length)
        : 'N/A',
      timeSeries: statsSamples,
    },
    screenshots,
    artifacts: {
      video: `${runId}-game-recording.webm`,
      report: `${runId}-report.json`,
    },
  };

  const reportPath = path.join(OUT_DIR, `${runId}-report.json`);
  fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
  console.log(`\n=== Report: ${reportPath} ===`);
  console.log(`Instances: ${report.instances}`);
  console.log(`Avg CPU: ${report.stats.avgCpu}% | Max CPU: ${report.stats.maxCpu}%`);
  console.log(`Avg RAM: ${report.stats.avgMemPercent}% | Max RAM: ${report.stats.maxMemMB}MB`);
  if (report.stats.avgGpu !== 'N/A') console.log(`Avg GPU: ${report.stats.avgGpu}%`);
  console.log(`Screenshots: ${screenshots.length}`);
  console.log('Done!');
}

main().catch(err => {
  console.error('Recording failed:', err);
  process.exit(1);
});
