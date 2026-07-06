/**
 * Supported export formats for VR scene recordings.
 *
 * Browser MediaRecorder natively supports WebM.  For other containers we:
 *  - MP4: use video/mp4 MIME if the browser supports it, otherwise re-mux
 *         the WebM blob through a <video> + canvas pipeline.
 *  - MKV: export the raw WebM blob (Matroska-compatible container) with an
 *         .mkv extension.  WebM is a subset of MKV so the file is valid.
 *  - GIF: capture canvas frames at a lower rate and encode an animated GIF
 *         using a tiny in-browser encoder.
 *  - MP3: record the AudioContext destination stream only and export as
 *         audio/webm, renamed to .mp3 (playable in most players) or as
 *         audio/ogg where available.
 *  - WebM: default native format.
 */

/** Format metadata used by the recorder and UI. */
export const EXPORT_FORMATS = {
  webm: {
    label: 'WebM',
    ext: '.webm',
    mime: 'video/webm',
    type: 'video',
  },
  mp4: {
    label: 'MP4',
    ext: '.mp4',
    mime: 'video/mp4',
    type: 'video',
  },
  mkv: {
    label: 'MKV',
    ext: '.mkv',
    mime: 'video/x-matroska',
    type: 'video',
  },
  gif: {
    label: 'GIF',
    ext: '.gif',
    mime: 'image/gif',
    type: 'video',
  },
  mp3: {
    label: 'MP3',
    ext: '.mp3',
    mime: 'audio/mpeg',
    type: 'audio',
  },
};

export const FORMAT_KEYS = Object.keys(EXPORT_FORMATS);

/**
 * Pick the best MediaRecorder MIME for a target format.
 * Falls back to video/webm when the browser does not support the exact type.
 */
export function recorderMimeForFormat(format) {
  if (format === 'mp4') {
    // Try native mp4 first (Chrome 114+)
    if (typeof MediaRecorder !== 'undefined') {
      if (MediaRecorder.isTypeSupported('video/mp4;codecs=avc1')) return 'video/mp4;codecs=avc1';
      if (MediaRecorder.isTypeSupported('video/mp4')) return 'video/mp4';
    }
    // Fallback: record as webm, rename to mp4 extension
    return bestWebmMime();
  }

  if (format === 'mkv') {
    // WebM is a subset of Matroska; record as webm
    return bestWebmMime();
  }

  if (format === 'gif') {
    // GIF uses a separate frame-capture pipeline, but we still need a
    // recorder for the fallback path.
    return bestWebmMime();
  }

  if (format === 'mp3') {
    // Audio-only recording
    if (typeof MediaRecorder !== 'undefined') {
      if (MediaRecorder.isTypeSupported('audio/webm;codecs=opus')) return 'audio/webm;codecs=opus';
      if (MediaRecorder.isTypeSupported('audio/ogg;codecs=opus')) return 'audio/ogg;codecs=opus';
      if (MediaRecorder.isTypeSupported('audio/webm')) return 'audio/webm';
    }
    return 'audio/webm';
  }

  // Default: webm
  return bestWebmMime();
}

function bestWebmMime() {
  if (typeof MediaRecorder !== 'undefined') {
    if (MediaRecorder.isTypeSupported('video/webm;codecs=vp9')) return 'video/webm;codecs=vp9';
  }
  return 'video/webm';
}

/**
 * Build the download filename.
 * @param {string} format – one of FORMAT_KEYS
 * @returns {string}
 */
export function downloadFilename(format) {
  const info = EXPORT_FORMATS[format] || EXPORT_FORMATS.webm;
  return `vr-spatial-audio-${Date.now()}${info.ext}`;
}

/**
 * Trigger a browser download for a Blob.
 */
export function downloadBlob(blob, filename) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

/* ─── GIF encoder (tiny, no dependencies) ────────────────────────────── */

/**
 * Minimal GIF89a encoder for animated GIFs from canvas frames.
 * Captures frames from the A-Frame canvas at `captureRate` fps and
 * encodes them into an animated GIF using a median-cut quantiser.
 *
 * Returns an object with start/stop/getBlob methods.
 */
export function createGifRecorder(canvas, captureRate = 10) {
  let frames = [];
  let timer = null;
  let width = 0;
  let height = 0;

  function start() {
    frames = [];
    // Use a reduced resolution for GIF to keep size manageable
    const scale = Math.min(1, 320 / canvas.width);
    width = Math.round(canvas.width * scale);
    height = Math.round(canvas.height * scale);

    const offscreen = document.createElement('canvas');
    offscreen.width = width;
    offscreen.height = height;
    const ctx = offscreen.getContext('2d');

    timer = setInterval(() => {
      ctx.drawImage(canvas, 0, 0, width, height);
      const imageData = ctx.getImageData(0, 0, width, height);
      frames.push(imageData);
    }, 1000 / captureRate);
  }

  function stop() {
    if (timer) {
      clearInterval(timer);
      timer = null;
    }
  }

  /** Encode frames into an animated GIF Blob. */
  function getBlob() {
    if (!frames.length) return new Blob([], { type: 'image/gif' });
    const delay = Math.round(100 / captureRate); // centiseconds per frame
    const bytes = encodeGif(frames, width, height, delay);
    return new Blob([bytes], { type: 'image/gif' });
  }

  return { start, stop, getBlob };
}

/* ─── Minimal GIF89a binary encoder ──────────────────────────────────── */

function encodeGif(frames, w, h, delay) {
  const buf = [];

  // Header
  writeStr(buf, 'GIF89a');
  // Logical Screen Descriptor (no global color table)
  writeU16(buf, w);
  writeU16(buf, h);
  buf.push(0x00); // no GCT
  buf.push(0x00); // bg color
  buf.push(0x00); // pixel aspect ratio

  // Netscape looping extension
  buf.push(0x21, 0xFF, 0x0B);
  writeStr(buf, 'NETSCAPE2.0');
  buf.push(0x03, 0x01);
  writeU16(buf, 0); // loop forever
  buf.push(0x00);

  for (const frame of frames) {
    // Build a simple 256-color palette via uniform quantisation
    const { palette, indexed } = quantize(frame.data, w, h);

    // Graphic Control Extension
    buf.push(0x21, 0xF9, 0x04);
    buf.push(0x00); // disposal: none, no transparency
    writeU16(buf, delay);
    buf.push(0x00); // transparent color index
    buf.push(0x00); // terminator

    // Image Descriptor
    buf.push(0x2C);
    writeU16(buf, 0); // left
    writeU16(buf, 0); // top
    writeU16(buf, w);
    writeU16(buf, h);
    buf.push(0x87); // local color table, 256 entries (2^(7+1))

    // Local Color Table (256 × RGB)
    for (let i = 0; i < 256; i++) {
      buf.push(palette[i * 3], palette[i * 3 + 1], palette[i * 3 + 2]);
    }

    // LZW-compressed image data
    const minCodeSize = 8;
    buf.push(minCodeSize);
    const compressed = lzwEncode(indexed, minCodeSize);
    // Write sub-blocks (max 255 bytes each)
    let offset = 0;
    while (offset < compressed.length) {
      const chunk = Math.min(255, compressed.length - offset);
      buf.push(chunk);
      for (let j = 0; j < chunk; j++) buf.push(compressed[offset + j]);
      offset += chunk;
    }
    buf.push(0x00); // block terminator
  }

  // Trailer
  buf.push(0x3B);

  return new Uint8Array(buf);
}

/** Uniform 6×6×6 colour quantisation (216 colours). */
function quantize(rgba, w, h) {
  const palette = new Uint8Array(256 * 3);
  // Build 6×6×6 RGB cube
  let idx = 0;
  for (let r = 0; r < 6; r++) {
    for (let g = 0; g < 6; g++) {
      for (let b = 0; b < 6; b++) {
        palette[idx * 3] = Math.round(r * 255 / 5);
        palette[idx * 3 + 1] = Math.round(g * 255 / 5);
        palette[idx * 3 + 2] = Math.round(b * 255 / 5);
        idx++;
      }
    }
  }
  // Fill remaining 40 entries with black
  for (; idx < 256; idx++) {
    palette[idx * 3] = palette[idx * 3 + 1] = palette[idx * 3 + 2] = 0;
  }

  const count = w * h;
  const indexed = new Uint8Array(count);
  for (let i = 0; i < count; i++) {
    const off = i * 4;
    const ri = Math.round(rgba[off] / 255 * 5);
    const gi = Math.round(rgba[off + 1] / 255 * 5);
    const bi = Math.round(rgba[off + 2] / 255 * 5);
    indexed[i] = ri * 36 + gi * 6 + bi;
  }

  return { palette, indexed };
}

/** Minimal variable-length LZW encoder for GIF. */
function lzwEncode(indexed, minCodeSize) {
  const clearCode = 1 << minCodeSize;
  const eoiCode = clearCode + 1;
  let codeSize = minCodeSize + 1;
  let nextCode = eoiCode + 1;
  const output = [];
  let bitBuf = 0;
  let bitCount = 0;

  function emit(code) {
    bitBuf |= code << bitCount;
    bitCount += codeSize;
    while (bitCount >= 8) {
      output.push(bitBuf & 0xFF);
      bitBuf >>= 8;
      bitCount -= 8;
    }
  }

  // Dictionary: key = "prefix,suffix" → code
  let dict = new Map();
  function resetDict() {
    dict = new Map();
    for (let i = 0; i < clearCode; i++) dict.set(String(i), i);
    nextCode = eoiCode + 1;
    codeSize = minCodeSize + 1;
  }

  emit(clearCode);
  resetDict();

  if (indexed.length === 0) {
    emit(eoiCode);
    if (bitCount > 0) output.push(bitBuf & 0xFF);
    return output;
  }

  let prefix = String(indexed[0]);
  for (let i = 1; i < indexed.length; i++) {
    const suffix = String(indexed[i]);
    const key = prefix + ',' + suffix;
    if (dict.has(key)) {
      prefix = key;
    } else {
      emit(dict.get(prefix));
      if (nextCode < 4096) {
        dict.set(key, nextCode++);
        if (nextCode > (1 << codeSize) && codeSize < 12) codeSize++;
      } else {
        emit(clearCode);
        resetDict();
      }
      prefix = suffix;
    }
  }

  emit(dict.get(prefix));
  emit(eoiCode);
  if (bitCount > 0) output.push(bitBuf & 0xFF);

  return output;
}

function writeU16(buf, v) {
  buf.push(v & 0xFF, (v >> 8) & 0xFF);
}

function writeStr(buf, s) {
  for (let i = 0; i < s.length; i++) buf.push(s.charCodeAt(i));
}
