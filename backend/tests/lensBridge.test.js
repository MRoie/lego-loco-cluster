const LensBridge = require('../services/lensBridge');

// Minimal fake framebuffer: solid RGB frame with controllable age.
function fakeFb({ width = 64, height = 48, ageMs = 0 } = {}) {
  const pixels = Buffer.alloc(width * height * 3, 200);
  const sends = [];
  return {
    width, height,
    getFrame: () => ({ width, height, channels: 3, pixels, ageMs }),
    sendPointer: (x, y, buttons) => sends.push({ x, y, buttons }),
    _sends: sends,
  };
}

describe('LensBridge control routing', () => {
  test('lens.move nudges the lens centre and clamps to [0,1]', () => {
    const fb = fakeFb();
    const bridge = new LensBridge({ framebuffer: fb, send: () => {} });
    bridge.cx = 0.95;
    bridge.handleMessage({ type: 'lens.move', dx: 1, dy: 0 });
    expect(bridge.cx).toBeLessThanOrEqual(1);
    expect(bridge.cx).toBeGreaterThan(0.95);
  });

  test('lens.pointer injects a mapped RFB pointer event', () => {
    const fb = fakeFb();
    const bridge = new LensBridge({ framebuffer: fb, send: () => {} });
    bridge.handleMessage({ type: 'lens.pointer', x: 0.5, y: 0.5, buttons: 1 });
    expect(fb._sends.length).toBe(1);
    expect(fb._sends[0].buttons).toBe(1);
    expect(fb._sends[0].x).toBeGreaterThanOrEqual(0);
    expect(fb._sends[0].x).toBeLessThanOrEqual(1);
  });

  test('mouse.button click injects press then release', () => {
    const fb = fakeFb();
    const bridge = new LensBridge({ framebuffer: fb, send: () => {} });
    bridge.handleMessage({ type: 'mouse.button', button: 'right', state: 'click' });
    expect(fb._sends.length).toBe(2);
    expect(fb._sends[0].buttons).toBe(4); // right down
    expect(fb._sends[1].buttons).toBe(0); // release
  });

  test('lens.inspect clicks at the lens centre', () => {
    const fb = fakeFb();
    const bridge = new LensBridge({ framebuffer: fb, send: () => {} });
    bridge.handleMessage({ type: 'lens.inspect' });
    expect(fb._sends.length).toBe(2); // down + up
  });

  test('invalid messages are ignored', () => {
    const fb = fakeFb();
    const bridge = new LensBridge({ framebuffer: fb, send: () => {} });
    expect(bridge.handleMessage({ type: 'garbage' })).toBeNull();
    expect(fb._sends.length).toBe(0);
  });
});

describe('LensBridge frame pacing', () => {
  test('emits a fresh frame on tick', async () => {
    const fb = fakeFb({ ageMs: 10 });
    const sent = [];
    const bridge = new LensBridge({ framebuffer: fb, send: (d) => sent.push(d), format: 'raw', size: 32 });
    await bridge._tick();
    expect(sent.length).toBe(1);
    expect(bridge.stats.sent).toBe(1);
    expect(Buffer.isBuffer(sent[0])).toBe(true);
  });

  test('drops stale frames instead of sending them', async () => {
    const fb = fakeFb({ ageMs: 999 });
    const sent = [];
    const bridge = new LensBridge({ framebuffer: fb, send: (d) => sent.push(d), format: 'raw', staleMs: 250 });
    await bridge._tick();
    expect(sent.length).toBe(0);
    expect(bridge.stats.droppedStale).toBe(1);
  });

  test('does not encode two frames concurrently', async () => {
    const fb = fakeFb({ ageMs: 10 });
    const bridge = new LensBridge({ framebuffer: fb, send: () => {}, format: 'raw' });
    bridge._encoding = true; // simulate an in-flight encode
    await bridge._tick();
    expect(bridge.stats.droppedBusy).toBe(1);
  });
});
