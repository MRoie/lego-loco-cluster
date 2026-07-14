/**
 * lensEncoder.js — encode a circular RGBA crop for the watch link.
 *
 * The watch wants a small (~400x400) image at ~8-12 fps. JPEG has no alpha, so
 * for the circular look we either (a) composite the masked pixels onto a solid
 * background and send JPEG, or (b) send PNG to preserve the transparent corners.
 * PNG is the default so the round bezel shows through; callers on a bandwidth
 * budget can request 'jpeg'.
 *
 * Encoding uses the `sharp` module when available and falls back to a tiny
 * built-in raw framing so the module loads (and unit-tests) without native deps.
 */

let sharp = null;
try { sharp = require('sharp'); } catch (e) { sharp = null; }

const DEFAULT_BG = { r: 0, g: 0, b: 0 };

/**
 * @param {{width:number,height:number,data:Buffer}} rgba  circularCrop() output
 * @param {object} [opts]
 * @param {'png'|'jpeg'|'raw'} [opts.format='png']
 * @param {number} [opts.quality=72] JPEG quality
 * @param {{r,g,b}} [opts.background] JPEG matte for masked corners
 * @returns {Promise<{format:string, mime:string, data:Buffer, encoder:string}>}
 */
async function encodeLensFrame(rgba, opts = {}) {
  const format = opts.format || 'png';
  if (format === 'raw' || !sharp) {
    // Framed raw RGBA: [4B width][4B height]['RGBA'][pixels]. Deterministic,
    // dependency-free — used by tests and as a fallback.
    const header = Buffer.alloc(12);
    header.writeUInt32BE(rgba.width, 0);
    header.writeUInt32BE(rgba.height, 4);
    header.write('RGBA', 8, 'ascii');
    return {
      format: 'raw',
      mime: 'application/octet-stream',
      data: Buffer.concat([header, rgba.data]),
      encoder: sharp ? 'raw(forced)' : 'raw(no-sharp)',
    };
  }

  const img = sharp(rgba.data, { raw: { width: rgba.width, height: rgba.height, channels: 4 } });
  if (format === 'jpeg') {
    const bg = opts.background || DEFAULT_BG;
    const data = await img.flatten({ background: bg }).jpeg({ quality: opts.quality || 72 }).toBuffer();
    return { format: 'jpeg', mime: 'image/jpeg', data, encoder: 'sharp' };
  }
  const data = await img.png({ compressionLevel: 6 }).toBuffer();
  return { format: 'png', mime: 'image/png', data, encoder: 'sharp' };
}

module.exports = { encodeLensFrame, hasSharp: () => !!sharp };
