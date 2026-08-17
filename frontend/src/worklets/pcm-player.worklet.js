/**
 * pcm-player.worklet.js — AudioWorkletProcessor that plays a raw s16le
 * interleaved-stereo PCM stream pushed over its message port.
 *
 * The stream arrives as WebSocket/TCP chunks with arbitrary byte boundaries,
 * at the emulator's rate (48 kHz), while the AudioContext runs at whatever
 * the OS gave it (44.1 kHz on plenty of hardware). So this processor:
 *
 *   - reassembles whole frames across chunk boundaries (a chunk can split a
 *     4-byte stereo frame anywhere — dropping the remainder would swap
 *     channels or shear samples in half),
 *   - converts s16 -> float32 and linearly resamples to the context rate at
 *     write time, so process() stays a plain ring-buffer read,
 *   - primes at ~120 ms before the first sample plays and re-primes after an
 *     underrun (silence instead of crackle),
 *   - drops the OLDEST audio once ~240 ms is buffered — buffered PCM can only
 *     ever be played late, so backlog is latency, never a resource.
 */

const RING_FRAMES = 32768; // ~683 ms @ 48 kHz — headroom over the 240 ms cap

class PCMPlayerProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.left = new Float32Array(RING_FRAMES);
    this.right = new Float32Array(RING_FRAMES);
    this.readPos = 0;
    this.writePos = 0;
    this.fill = 0; // frames currently buffered

    // `sampleRate` is the AudioWorkletGlobalScope's context rate.
    this.primeFrames = Math.min(Math.round(sampleRate * 0.12), RING_FRAMES >> 2);
    this.maxFrames = Math.min(Math.round(sampleRate * 0.24), RING_FRAMES - 128);
    this.primed = false;

    this.inputRate = sampleRate; // until a {type:'format'} message says otherwise
    // Linear-resampler state carried across chunks: the last input frame and
    // the fractional read position between it and the next chunk's first frame.
    this.phase = 0;
    this.prevL = 0;
    this.prevR = 0;

    // Up to 3 leftover bytes of a split frame, prepended to the next chunk.
    this.pending = new Uint8Array(4);
    this.pendingLen = 0;

    this.port.onmessage = (e) => {
      const data = e.data;
      if (data && data.type === 'format') {
        if (data.rate > 0 && data.rate !== this.inputRate) {
          this.inputRate = data.rate;
          this.phase = 0;
        }
        return;
      }
      if (data instanceof ArrayBuffer) this._write(data);
    };
  }

  _write(buf) {
    let bytes = new Uint8Array(buf);
    if (this.pendingLen > 0) {
      const merged = new Uint8Array(this.pendingLen + bytes.length);
      merged.set(this.pending.subarray(0, this.pendingLen));
      merged.set(bytes, this.pendingLen);
      bytes = merged;
      this.pendingLen = 0;
    }
    const usable = bytes.length & ~3; // whole 4-byte stereo frames only
    const rem = bytes.length - usable;
    if (rem > 0) {
      this.pending.set(bytes.subarray(usable));
      this.pendingLen = rem;
    }
    if (usable === 0) return;

    // bytes always starts at offset 0 of its own buffer, so the view is aligned.
    const s16 = new Int16Array(bytes.buffer, bytes.byteOffset, usable >> 1);
    const frames = usable >> 2;

    if (this.inputRate === sampleRate) {
      for (let i = 0; i < frames; i++) {
        this._push(s16[2 * i] / 32768, s16[2 * i + 1] / 32768);
      }
    } else {
      // Linear resample. Virtual input timeline: position 0 is the previous
      // chunk's last frame, position k (k >= 1) is this chunk's frame k-1 —
      // so interpolation is seamless across chunk boundaries.
      const step = this.inputRate / sampleRate;
      let t = this.phase;
      while (t < frames) {
        const i = Math.floor(t);
        const frac = t - i;
        const l0 = i === 0 ? this.prevL : s16[2 * (i - 1)] / 32768;
        const r0 = i === 0 ? this.prevR : s16[2 * (i - 1) + 1] / 32768;
        const l1 = s16[2 * i] / 32768;
        const r1 = s16[2 * i + 1] / 32768;
        this._push(l0 + (l1 - l0) * frac, r0 + (r1 - r0) * frac);
        t += step;
      }
      this.phase = t - frames;
      this.prevL = s16[2 * (frames - 1)] / 32768;
      this.prevR = s16[2 * (frames - 1) + 1] / 32768;
    }
  }

  _push(l, r) {
    if (this.fill >= this.maxFrames) {
      // Past the latency cap: advance the read pointer over the oldest audio.
      const drop = this.fill - this.maxFrames + 1;
      this.readPos = (this.readPos + drop) % RING_FRAMES;
      this.fill -= drop;
    }
    this.left[this.writePos] = l;
    this.right[this.writePos] = r;
    this.writePos = (this.writePos + 1) % RING_FRAMES;
    this.fill++;
  }

  process(_inputs, outputs) {
    const out = outputs[0];
    if (!out || out.length === 0) return true;
    const n = out[0].length;

    if (!this.primed) {
      if (this.fill >= this.primeFrames) {
        this.primed = true;
      } else {
        for (const ch of out) ch.fill(0);
        return true;
      }
    }

    if (this.fill < n) {
      // Underrun: a silent block and a fresh prime beat a stuttering crawl.
      for (const ch of out) ch.fill(0);
      this.primed = false;
      return true;
    }

    const stereo = out.length > 1;
    for (let i = 0; i < n; i++) {
      const l = this.left[this.readPos];
      const r = this.right[this.readPos];
      if (stereo) {
        out[0][i] = l;
        out[1][i] = r;
      } else {
        out[0][i] = 0.5 * (l + r);
      }
      this.readPos = (this.readPos + 1) % RING_FRAMES;
    }
    this.fill -= n;
    return true;
  }
}

registerProcessor('pcm-player', PCMPlayerProcessor);
