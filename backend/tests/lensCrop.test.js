const { lensSourceRect, circularCrop, lensPointToFramebuffer } = require('../services/lensCrop');

describe('lensSourceRect', () => {
  const fb = { fbWidth: 1024, fbHeight: 768 };

  test('centres the source rect and stays inside the framebuffer', () => {
    const r = lensSourceRect({ ...fb, cx: 0.5, cy: 0.5 });
    expect(r.sw).toBe(r.sh); // square
    expect(r.sx + r.sw).toBeLessThanOrEqual(1024);
    expect(r.sy + r.sh).toBeLessThanOrEqual(768);
    // centred: rect centre ~= framebuffer centre
    expect(r.sx + r.sw / 2).toBeCloseTo(512, -1);
  });

  test('clamps against the top-left corner', () => {
    const r = lensSourceRect({ ...fb, cx: 0, cy: 0 });
    expect(r.sx).toBe(0);
    expect(r.sy).toBe(0);
  });

  test('clamps against the bottom-right corner', () => {
    const r = lensSourceRect({ ...fb, cx: 1, cy: 1 });
    expect(r.sx + r.sw).toBe(1024);
    expect(r.sy + r.sh).toBe(768);
  });

  test('higher zoom yields a smaller source rect (more magnification)', () => {
    const wide = lensSourceRect({ ...fb, cx: 0.5, cy: 0.5, zoom: 1 });
    const tight = lensSourceRect({ ...fb, cx: 0.5, cy: 0.5, zoom: 4 });
    expect(tight.sw).toBeLessThan(wide.sw);
  });

  test('source rect never exceeds the framebuffer even at extreme zoom-out', () => {
    const r = lensSourceRect({ ...fb, cx: 0.5, cy: 0.5, zoom: 0.25 });
    expect(r.sw).toBeLessThanOrEqual(768); // min dimension
  });
});

describe('circularCrop', () => {
  // 4x4 solid-white RGB framebuffer
  const fbWidth = 4, fbHeight = 4, channels = 3;
  const pixels = Buffer.alloc(fbWidth * fbHeight * channels, 255);

  test('produces an RGBA buffer of the requested size', () => {
    const rect = { sx: 0, sy: 0, sw: 4, sh: 4 };
    const out = circularCrop({ pixels, fbWidth, fbHeight, channels, rect, size: 8 });
    expect(out.width).toBe(8);
    expect(out.channels).toBe(4);
    expect(out.data.length).toBe(8 * 8 * 4);
  });

  test('corners are transparent, centre is opaque (circular mask)', () => {
    const rect = { sx: 0, sy: 0, sw: 4, sh: 4 };
    const size = 8;
    const out = circularCrop({ pixels, fbWidth, fbHeight, channels, rect, size });
    const alphaAt = (x, y) => out.data[(y * size + x) * 4 + 3];
    expect(alphaAt(0, 0)).toBe(0);            // corner masked
    expect(alphaAt(size - 1, size - 1)).toBe(0);
    expect(alphaAt(size / 2, size / 2)).toBe(255); // centre visible
  });

  test('non-circular mode fills every pixel opaque', () => {
    const rect = { sx: 0, sy: 0, sw: 4, sh: 4 };
    const out = circularCrop({ pixels, fbWidth, fbHeight, channels, rect, size: 6, circular: false });
    for (let i = 3; i < out.data.length; i += 4) expect(out.data[i]).toBe(255);
  });
});

describe('lensPointToFramebuffer', () => {
  test('a tap at the lens centre maps to the source-rect centre', () => {
    const rect = { sx: 300, sy: 200, sw: 200, sh: 200 };
    const p = lensPointToFramebuffer({ lensX: 0.5, lensY: 0.5, rect, fbWidth: 1024, fbHeight: 768 });
    expect(p.x).toBeCloseTo(400 / 1024, 5);
    expect(p.y).toBeCloseTo(300 / 768, 5);
  });

  test('a tap at the lens top-left maps to the source-rect origin', () => {
    const rect = { sx: 300, sy: 200, sw: 200, sh: 200 };
    const p = lensPointToFramebuffer({ lensX: 0, lensY: 0, rect, fbWidth: 1024, fbHeight: 768 });
    expect(p.x).toBeCloseTo(300 / 1024, 5);
    expect(p.y).toBeCloseTo(200 / 768, 5);
  });
});
