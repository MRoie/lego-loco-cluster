const StreamQualityMonitor = require('../services/streamQualityMonitor');

describe('SLA scoring (streamQualityMonitor)', () => {
  let monitor;

  beforeEach(() => {
    monitor = new StreamQualityMonitor('../config', null);
  });

  afterEach(() => {
    monitor.stop();
  });

  const fullMetrics = () => ({
    instanceId: 'instance-0',
    availability: { vnc: true, stream: true, audio: true, controls: true },
    quality: { connectionLatency: 50, videoFrameRate: 25 },
  });

  test('perfect instance scores 100', () => {
    expect(monitor.computeSlaScore(fullMetrics())).toBe(100);
  });

  test('vnc-down instance loses availability points', () => {
    const m = fullMetrics();
    m.availability = { vnc: false, stream: false, audio: false, controls: false };
    // latency 30 + fps 20 remain
    expect(monitor.computeSlaScore(m)).toBe(50);
  });

  test('latency degrades score linearly past 100ms', () => {
    const m = fullMetrics();
    m.quality.connectionLatency = 550; // halfway between 100 and 1000
    expect(monitor.computeSlaScore(m)).toBe(85); // 50 avail + 15 latency + 20 fps
  });

  test('latency past 1000ms earns zero latency points', () => {
    const m = fullMetrics();
    m.quality.connectionLatency = 5000;
    expect(monitor.computeSlaScore(m)).toBe(70);
  });

  test('missing latency contributes nothing', () => {
    const m = fullMetrics();
    m.quality.connectionLatency = null;
    expect(monitor.computeSlaScore(m)).toBe(70);
  });

  test('frame rate scales to 20 points at 15fps', () => {
    const m = fullMetrics();
    m.quality.videoFrameRate = 7.5;
    expect(monitor.computeSlaScore(m)).toBe(90); // 50 + 30 + 10
  });

  test('summary aggregates average SLA and lists degraded instances', () => {
    const good = fullMetrics();
    good.slaScore = monitor.computeSlaScore(good);

    const bad = fullMetrics();
    bad.instanceId = 'instance-1';
    bad.availability = { vnc: false, stream: false, audio: false, controls: false };
    bad.quality = { connectionLatency: null, videoFrameRate: 0 };
    bad.slaScore = monitor.computeSlaScore(bad);

    monitor.metrics.set('instance-0', good);
    monitor.metrics.set('instance-1', bad);

    const summary = monitor.getQualitySummary();
    expect(summary.averageSlaScore).toBe(50); // (100 + 0) / 2
    expect(summary.degradedInstances).toEqual([
      { instanceId: 'instance-1', slaScore: 0 },
    ]);
  });

  test('alert webhook fires below threshold and respects cooldown', async () => {
    monitor.alertWebhookUrl = 'http://alerts.example/hook';
    monitor.slaAlertThreshold = 70;
    global.fetch = jest.fn().mockResolvedValue({ ok: true });

    const bad = fullMetrics();
    bad.slaScore = 10;

    monitor.evaluateSlaAlert(bad);
    monitor.evaluateSlaAlert(bad); // within cooldown — must not re-fire

    expect(global.fetch).toHaveBeenCalledTimes(1);
    const [url, opts] = global.fetch.mock.calls[0];
    expect(url).toBe('http://alerts.example/hook');
    const payload = JSON.parse(opts.body);
    expect(payload.type).toBe('sla_degraded');
    expect(payload.instanceId).toBe('instance-0');
    expect(payload.slaScore).toBe(10);
  });

  test('no webhook configured means no alert attempt', () => {
    monitor.alertWebhookUrl = null;
    global.fetch = jest.fn();

    const bad = fullMetrics();
    bad.slaScore = 10;
    monitor.evaluateSlaAlert(bad);

    expect(global.fetch).not.toHaveBeenCalled();
  });

  test('healthy score above threshold does not alert', () => {
    monitor.alertWebhookUrl = 'http://alerts.example/hook';
    global.fetch = jest.fn();

    const good = fullMetrics();
    good.slaScore = 95;
    monitor.evaluateSlaAlert(good);

    expect(global.fetch).not.toHaveBeenCalled();
  });
});
