// Real lens-crop e2e: run the actual backend lensCrop.js on a real Win98/Loco
// framebuffer (PPM), producing circular crops + full-frame-with-marker images.
const fs = require('fs');
const { lensSourceRect, circularCrop } = require('../../backend/services/lensCrop');
let sharp; try { sharp = require('sharp'); } catch (e) { sharp = require('sharp'); }

function readPPM(path) {
  const buf = fs.readFileSync(path);
  // parse P6 header
  let pos = 0;
  function token() {
    while (buf[pos] === 0x20 || buf[pos] === 0x0a || buf[pos] === 0x0d || buf[pos] === 0x09) pos++;
    let s = pos; while (!(buf[pos] === 0x20 || buf[pos] === 0x0a || buf[pos] === 0x0d || buf[pos] === 0x09)) pos++;
    return buf.slice(s, pos).toString();
  }
  const magic = token(); const w = parseInt(token()); const h = parseInt(token()); token(); pos++;
  return { w, h, data: buf.slice(pos), magic };
}

async function main() {
  const { w, h, data } = readPPM('/w/gc7.ppm');
  console.log(`framebuffer ${w}x${h}`);

  // Interesting lens targets over the Loco city (normalized centres).
  const targets = [
    { name: 'houses-cluster', cx: 0.33, cy: 0.20, zoom: 2.5 },
    { name: 'rail-junction',  cx: 0.34, cy: 0.65, zoom: 3.0 },
    { name: 'city-centre',    cx: 0.50, cy: 0.40, zoom: 2.0 },
    { name: 'desktop-icons',  cx: 0.09, cy: 0.12, zoom: 2.0 },
  ];

  for (const t of targets) {
    const rect = lensSourceRect({ fbWidth: w, fbHeight: h, cx: t.cx, cy: t.cy, zoom: t.zoom });
    // Real backend circular crop → 400x400 RGBA with transparent corners.
    const rgba = circularCrop({ pixels: data, fbWidth: w, fbHeight: h, channels: 3, rect, size: 400, circular: true });
    await sharp(rgba.data, { raw: { width: 400, height: 400, channels: 4 } })
      .png().toFile(`/w/lens-${t.name}-crop.png`);

    // Full frame with the source rect outlined (the "area of screen in game").
    const marked = Buffer.from(data);
    const stroke = (x, y) => { const i = (y * w + x) * 3; if (i + 2 < marked.length) { marked[i] = 255; marked[i+1] = 0; marked[i+2] = 0; } };
    for (let x = rect.sx; x < rect.sx + rect.sw; x++) { for (let d = 0; d < 3; d++) { stroke(x, rect.sy + d); stroke(x, rect.sy + rect.sh - 1 - d); } }
    for (let y = rect.sy; y < rect.sy + rect.sh; y++) { for (let d = 0; d < 3; d++) { stroke(rect.sx + d, y); stroke(rect.sx + rect.sw - 1 - d, y); } }
    await sharp(marked, { raw: { width: w, height: h, channels: 3 } }).png().toFile(`/w/lens-${t.name}-region.png`);

    console.log(`${t.name}: rect sx=${rect.sx} sy=${rect.sy} ${rect.sw}x${rect.sh} -> 400x400 circular crop`);
  }
  console.log('done');
}
main().catch(e => { console.error(e); process.exit(1); });
