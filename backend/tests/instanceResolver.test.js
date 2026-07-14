const { InstanceResolver, parseRegistry } = require('../services/instanceResolver');

describe('parseRegistry', () => {
  test('JSON with host/port objects', () => {
    const r = parseRegistry('{"local":{"host":"127.0.0.1","port":5901}}');
    expect(r.local).toEqual({ host: '127.0.0.1', port: 5901, password: undefined });
  });

  test('JSON shorthand host:port strings', () => {
    const r = parseRegistry('{"local":"10.0.0.5:5902"}');
    expect(r.local).toEqual({ host: '10.0.0.5', port: 5902 });
  });

  test('CSV shorthand', () => {
    const r = parseRegistry('a=127.0.0.1:5901,b=127.0.0.1:5902');
    expect(r.a).toEqual({ host: '127.0.0.1', port: 5901 });
    expect(r.b).toEqual({ host: '127.0.0.1', port: 5902 });
  });

  test('defaults missing port to 5901', () => {
    expect(parseRegistry('{"x":"host-only"}').x).toEqual({ host: 'host-only', port: 5901 });
  });

  test('empty spec yields empty registry', () => {
    expect(parseRegistry('')).toEqual({});
    expect(parseRegistry(undefined)).toEqual({});
  });
});

describe('InstanceResolver', () => {
  test('static mode resolves from the registry', async () => {
    const r = new InstanceResolver({ mode: 'static', registry: '{"local":"127.0.0.1:5901"}' });
    expect(r.mode).toBe('static');
    expect(await r.resolve('local')).toEqual({ host: '127.0.0.1', port: 5901 });
    expect(await r.resolve('nope')).toBeNull();
    expect(r.listStaticInstances()).toEqual(['local']);
  });

  test('auto mode picks static when a registry is present', () => {
    const r = new InstanceResolver({ registry: '{"local":"127.0.0.1:5901"}', k8sResolver: async () => null });
    expect(r.mode).toBe('static');
  });

  test('auto mode falls back to k8s with no registry', async () => {
    const k8s = jest.fn(async (id) => ({ host: 'pod-ip', port: 5901 }));
    const r = new InstanceResolver({ registry: '', k8sResolver: k8s });
    expect(r.mode).toBe('k8s');
    expect(await r.resolve('instance-0')).toEqual({ host: 'pod-ip', port: 5901 });
    expect(k8s).toHaveBeenCalledWith('instance-0');
  });

  test('k8s mode with no resolver returns null', async () => {
    const r = new InstanceResolver({ mode: 'k8s' });
    expect(await r.resolve('x')).toBeNull();
  });
});
