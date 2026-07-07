/**
 * lensCrop.js — pure geometry for the circular "Loco Lens" watch crop.
 *
 * Given a source RGBA/RGB framebuffer and a normalized lens centre, produce a
 * square crop of `size` px with a circular alpha mask (corners transparent),
 * matching the in-game inspection-magnifier look on the round M5Stack display.
 *
 * No image-encoding or I/O here — this is deterministic math so it can be
 * unit-tested without a framebuffer source or JPEG encoder.
 */

const { clamp } = require('../protocol/watchProtocol');

/**
 * Map a normalized lens centre + zoom to an integer source-rectangle.
 *
 * @param {object} p
 * @param {number} p.fbWidth   source framebuffer width
 * @param {number} p.fbHeight  source framebuffer height
 * @param {number} p.cx        lens centre x, normalized [0,1]
 * @param {number} p.cy        lens centre y, normalized [0,1]
 * @param {number} [p.zoom=1]  >1 magnifies (smaller source rect), <1 zooms out
 * @param {number} [p.baseFraction=0.35] source rect edge as a fraction of the
 *                 smaller framebuffer dimension at zoom=1
 * @returns {{sx:number, sy:number, sw:number, sh:number}} clamped to the fb
 */
function lensSourceRect({ fbWidth, fbHeight, cx, cy, zoom = 1, baseFraction = 0.35 }) {
  const z = clamp(zoom, 0.25, 8) || 1;
  const minDim = Math.min(fbWidth, fbHeight);
  let edge = Math.round((minDim * baseFraction) / z);
  edge = Math.max(16, Math.min(edge, minDim)); // never larger than the fb

  const centreX = clamp(cx, 0, 1) * fbWidth;
  const centreY = clamp(cy, 0, 1) * fbHeight;

  let sx = Math.round(centreX - edge / 2);
  let sy = Math.round(centreY - edge / 2);
  // Keep the rect fully inside the framebuffer.
  sx = Math.max(0, Math.min(sx, fbWidth - edge));
  sy = Math.max(0, Math.min(sy, fbHeight - edge));
  return { sx, sy, sw: edge, sh: edge };
}

/**
 * Extract + scale a circular crop from a raw framebuffer into an RGBA buffer.
 *
 * @param {object} p
 * @param {Buffer|Uint8Array} p.pixels raw framebuffer, row-major
 * @param {number} p.fbWidth
 * @param {number} p.fbHeight
 * @param {number} p.channels 3 (RGB) or 4 (RGBA) in the source
 * @param {object} p.rect     from lensSourceRect()
 * @param {number} p.size     output edge in px (e.g. 400)
 * @param {boolean} [p.circular=true] mask corners to transparent
 * @returns {{width:number, height:number, channels:4, data:Buffer}}
 */
function circularCrop({ pixels, fbWidth, fbHeight, channels, rect, size, circular = true }) {
  const out = Buffer.alloc(size * size * 4);
  const { sx, sy, sw, sh } = rect;
  const r = size / 2;
  const r2 = r * r;

  for (let oy = 0; oy < size; oy++) {
    // Nearest-neighbour sample (fast; watch crop is small and lossy anyway).
    const syPix = sy + Math.min(sh - 1, Math.floor((oy / size) * sh));
    for (let ox = 0; ox < size; ox++) {
      const oi = (oy * size + ox) * 4;
      if (circular) {
        const ddx = ox - r + 0.5;
        const ddy = oy - r + 0.5;
        if (ddx * ddx + ddy * ddy > r2) {
          out[oi] = 0; out[oi + 1] = 0; out[oi + 2] = 0; out[oi + 3] = 0;
          continue;
        }
      }
      const sxPix = sx + Math.min(sw - 1, Math.floor((ox / size) * sw));
      const si = (syPix * fbWidth + sxPix) * channels;
      out[oi] = pixels[si];
      out[oi + 1] = pixels[si + 1];
      out[oi + 2] = pixels[si + 2];
      out[oi + 3] = 255;
    }
  }
  return { width: size, height: size, channels: 4, data: out };
}

/**
 * Translate a watch-normalized pointer within the LENS into a framebuffer-
 * normalized pointer, so a tap on the round display maps to the correct guest
 * pixel. Inputs and output are all in [0,1].
 */
function lensPointToFramebuffer({ lensX, lensY, rect, fbWidth, fbHeight }) {
  const { sx, sy, sw, sh } = rect;
  const fbX = (sx + clamp(lensX, 0, 1) * sw) / fbWidth;
  const fbY = (sy + clamp(lensY, 0, 1) * sh) / fbHeight;
  return { x: clamp(fbX, 0, 1), y: clamp(fbY, 0, 1) };
}

module.exports = { lensSourceRect, circularCrop, lensPointToFramebuffer };
