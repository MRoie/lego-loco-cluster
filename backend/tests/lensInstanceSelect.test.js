const { handleLensConnection, openBridges } = require('../routes/watch');

// Fake ws (EventEmitter-ish) capturing sent messages.
function fakeWs() {
  const handlers = {};
  return {
    OPEN: 1, readyState: 1, sent: [],
    on(ev, fn) { handlers[ev] = fn; },
    emit(ev, arg) { if (handlers[ev]) return handlers[ev](arg); },
    send(m) { this.sent.push(m); },
    close() { this.closed = true; },
  };
}

// Mock RfbFramebuffer + LensBridge that record lifecycle.
function makeDeps(log) {
  class FB {
    constructor(ep) { this.ep = ep; log.push(`fb:new:${ep.host}:${ep.port}`); }
    connect() { log.push(`fb:connect:${this.ep.host}`); }
    close() { log.push(`fb:close:${this.ep.host}`); }
    getFrame() { return null; }
  }
  class Bridge {
    constructor({ framebuffer }) { this.fb = framebuffer; this.stats = {}; }
    start() { log.push(`bridge:start:${this.fb.ep.host}`); }
    stop() { log.push(`bridge:stop:${this.fb.ep.host}`); }
    handleMessage() {}
  }
  return { RfbFramebuffer: FB, LensBridge: Bridge };
}

describe('lens instance.select re-points the RFB', () => {
  afterEach(() => openBridges.clear());

  test('connects to the initial instance, then switches on instance.select', async () => {
    const log = [];
    const deps = makeDeps(log);
    const registry = { 'instance-0': { host: 'host0', port: 5901 }, 'instance-1': { host: 'host1', port: 5902 } };
    const resolver = async (id) => registry[id] || null;
    const ws = fakeWs();

    await handleLensConnection(ws, 'instance-0', resolver, deps);
    expect(log).toContain('fb:new:host0:5901');
    expect(log).toContain('bridge:start:host0');
    expect(ws.sent.some((m) => m.includes('"instance.active"') && m.includes('instance-0'))).toBe(true);

    log.length = 0;
    await ws.emit('message', JSON.stringify({ type: 'instance.select', id: 'instance-1' }));
    // old torn down, new connected
    expect(log).toContain('bridge:stop:host0');
    expect(log).toContain('fb:close:host0');
    expect(log).toContain('fb:new:host1:5902');
    expect(log).toContain('bridge:start:host1');
    expect(ws.sent.some((m) => m.includes('"instance.active"') && m.includes('instance-1'))).toBe(true);
  });

  test('closes when the initial instance cannot be resolved', async () => {
    const deps = makeDeps([]);
    const ws = fakeWs();
    await handleLensConnection(ws, 'ghost', async () => null, deps);
    expect(ws.closed).toBe(true);
    expect(ws.sent.some((m) => m.includes('no VNC endpoint'))).toBe(true);
  });
});
