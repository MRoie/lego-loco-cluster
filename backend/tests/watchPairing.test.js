const { WatchPairing } = require('../services/watchPairing');

describe('WatchPairing', () => {
  test('redeem returns the bound instance and consumes the code', () => {
    const wp = new WatchPairing();
    wp.issueCode('ABC123', 'instance-0', 1000);
    expect(wp.redeem('ABC123', 'watch-1', 1500)).toBe('instance-0');
    // single-use: a second redeem fails
    expect(wp.redeem('ABC123', 'watch-2', 1600)).toBeNull();
    expect(wp.getInstanceFor('watch-1')).toBe('instance-0');
  });

  test('codes expire after the TTL', () => {
    const wp = new WatchPairing({ ttlMs: 1000 });
    wp.issueCode('EXP111', 'instance-1', 0);
    expect(wp.redeem('EXP111', 'watch-9', 2000)).toBeNull(); // 2s > 1s TTL
  });

  test('issuing prunes expired codes so the map cannot grow unbounded', () => {
    const wp = new WatchPairing({ ttlMs: 1000 });
    wp.issueCode('OLD001', 'instance-1', 0);
    wp.issueCode('OLD002', 'instance-1', 100);
    expect(wp.codes.size).toBe(2);
    wp.issueCode('NEW001', 'instance-2', 5000); // prunes the two stale ones
    expect(wp.codes.size).toBe(1);
    expect([...wp.codes.keys()]).toEqual(['NEW001']);
  });

  test('retarget moves a paired watch to another instance', () => {
    const wp = new WatchPairing();
    wp.issueCode('RT0001', 'instance-0', 0);
    wp.redeem('RT0001', 'watch-1', 10);
    expect(wp.retarget('watch-1', 'instance-3')).toBe(true);
    expect(wp.getInstanceFor('watch-1')).toBe('instance-3');
    expect(wp.retarget('watch-unknown', 'instance-3')).toBe(false);
  });
});
