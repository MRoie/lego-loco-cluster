const { parseWatchMessage, isControlMessage, BUTTON_BITS } = require('../protocol/watchProtocol');

describe('watchProtocol.parseWatchMessage', () => {
  test('rejects non-JSON strings', () => {
    expect(parseWatchMessage('{not json').ok).toBe(false);
  });

  test('rejects unknown types', () => {
    expect(parseWatchMessage({ type: 'nope' })).toEqual({ ok: false, error: 'unknown type: nope' });
  });

  test('clamps lens.move deltas into [-1,1]', () => {
    const r = parseWatchMessage({ type: 'lens.move', dx: 5, dy: -9 });
    expect(r.ok).toBe(true);
    expect(r.msg).toEqual({ type: 'lens.move', dx: 1, dy: -1 });
  });

  test('clamps lens.pointer coords into [0,1] and masks buttons', () => {
    const r = parseWatchMessage({ type: 'lens.pointer', x: 1.4, y: -0.2, buttons: 0xff });
    expect(r.msg).toEqual({ type: 'lens.pointer', x: 1, y: 0, buttons: 0x7 });
  });

  test('accepts a JSON string payload', () => {
    const r = parseWatchMessage('{"type":"lens.inspect"}');
    expect(r).toEqual({ ok: true, msg: { type: 'lens.inspect' } });
  });

  test('instance.select requires a non-empty id', () => {
    expect(parseWatchMessage({ type: 'instance.select' }).ok).toBe(false);
    expect(parseWatchMessage({ type: 'instance.select', id: 'instance-2' }).msg.id).toBe('instance-2');
  });

  test('mouse.button normalizes unknown button/state to defaults', () => {
    const r = parseWatchMessage({ type: 'mouse.button', button: 'x', state: 'y' });
    expect(r.msg).toEqual({ type: 'mouse.button', button: 'left', state: 'click' });
  });

  test('control messages take priority over keepalives', () => {
    expect(isControlMessage('lens.pointer')).toBe(true);
    expect(isControlMessage('watch.ping')).toBe(false);
    expect(isControlMessage('watch.hello')).toBe(false);
  });

  test('button bit map is stable', () => {
    expect(BUTTON_BITS).toEqual({ left: 1, middle: 2, right: 4 });
  });
});
