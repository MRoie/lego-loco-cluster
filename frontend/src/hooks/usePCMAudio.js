import { useEffect, useRef, useState, useCallback } from 'react';
import { createLogger } from '../utils/logger';

const logger = createLogger('usePCMAudio');

// audioWorklet.addModule() is per-context and idempotent-but-not-cheap; keyed
// on the context so N tiles sharing one context load the module exactly once.
const workletLoads = new WeakMap();
function ensureWorklet(ctx) {
  let load = workletLoads.get(ctx);
  if (!load) {
    load = ctx.audioWorklet.addModule(
      new URL('../worklets/pcm-player.worklet.js', import.meta.url),
    );
    workletLoads.set(ctx, load);
  }
  return load;
}

/**
 * Guest audio for one emulator instance: a WebSocket of raw s16le PCM from
 * /proxy/audio/<id>/ fed into an AudioWorklet player.
 *
 * The first WS frame is a JSON {type:'format', rate, channels, format}
 * message from the backend; everything after it is binary PCM, transferred
 * (not copied) to the worklet's port.
 *
 * Returns:
 *   sourceNode  - GainNode carrying the stream; hand it to useSpatialAudio's
 *                 options.sourceNode, or leave options.connect=true to play
 *                 it straight to the context's destination
 *   audioLevel  - 0..1 RMS meter, tapped BEFORE the gain so activity shows
 *                 even while muted
 *   setVolume   - ramp the gain (0..1+)
 *   resume      - resume a suspended context (autoplay-policy unlock)
 *   isReady     - worklet built and wired
 *
 * @param {string} instanceId
 * @param {AudioContext} [sharedCtx] - optional shared AudioContext
 * @param {object} [options]
 * @param {boolean} [options.enabled=true] - master switch
 * @param {boolean} [options.createContext=true] - build an own context when no
 *   sharedCtx; pass false to wait for one (VR passes the shared ctx in later)
 * @param {boolean} [options.connect=false] - wire gain -> ctx.destination
 */
export default function usePCMAudio(instanceId, sharedCtx = null, options = {}) {
  const { enabled = true, createContext = true, connect = false } = options;

  const [sourceNode, setSourceNode] = useState(null);
  const [audioLevel, setAudioLevel] = useState(0);
  const [isReady, setIsReady] = useState(false);

  const ctxRef = useRef(null);
  const gainRef = useRef(null);

  useEffect(() => {
    if (!instanceId || !enabled) return undefined;

    const ctx =
      sharedCtx ||
      (createContext
        ? new (window.AudioContext || window.webkitAudioContext)()
        : null);
    if (!ctx) return undefined; // no shared ctx yet — re-run when it arrives

    const ownsCtx = !sharedCtx;
    ctxRef.current = ctx;

    let cancelled = false;
    let ws = null;
    let workletNode = null;
    let gain = null;
    let analyser = null;
    let meterTimer = null;
    let reconnectTimer = null;
    let reconnectAttempt = 0;
    const MAX_RECONNECT_ATTEMPTS = 50;
    const BASE_DELAY = 1000;
    const MAX_DELAY = 15000;

    const scheduleReconnect = () => {
      if (cancelled || reconnectTimer) return;
      if (reconnectAttempt >= MAX_RECONNECT_ATTEMPTS) {
        logger.error('PCM audio: max reconnect attempts reached', { instanceId });
        return;
      }
      const exponential = BASE_DELAY * Math.pow(2, reconnectAttempt);
      const jitter = Math.random() * 0.3 * exponential;
      const delay = Math.min(exponential + jitter, MAX_DELAY);
      reconnectAttempt++;
      reconnectTimer = setTimeout(() => {
        reconnectTimer = null;
        openSocket();
      }, delay);
    };

    const openSocket = () => {
      if (cancelled || !workletNode) return;
      const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
      const wsUrl = `${protocol}//${window.location.host}/proxy/audio/${instanceId}/`;
      ws = new WebSocket(wsUrl);
      ws.binaryType = 'arraybuffer';

      ws.onopen = () => {
        reconnectAttempt = 0;
        logger.info('PCM audio connected', { instanceId });
      };
      ws.onmessage = (e) => {
        if (cancelled || !workletNode) return;
        if (typeof e.data === 'string') {
          // The one text frame: stream format from the backend.
          try {
            const msg = JSON.parse(e.data);
            if (msg && msg.type === 'format') workletNode.port.postMessage(msg);
          } catch {
            /* not ours — ignore */
          }
          return;
        }
        // Transfer, don't copy: this runs for every PCM chunk.
        workletNode.port.postMessage(e.data, [e.data]);
      };
      ws.onerror = () => {};
      ws.onclose = () => {
        if (!cancelled) scheduleReconnect();
      };
    };

    ensureWorklet(ctx)
      .then(() => {
        if (cancelled || ctx.state === 'closed') return;

        workletNode = new AudioWorkletNode(ctx, 'pcm-player', {
          numberOfInputs: 0,
          numberOfOutputs: 1,
          outputChannelCount: [2],
        });

        gain = ctx.createGain();
        gain.gain.setValueAtTime(1, ctx.currentTime);

        analyser = ctx.createAnalyser();
        analyser.fftSize = 512;

        workletNode.connect(gain);
        workletNode.connect(analyser); // pre-gain tap: meter survives mute
        if (connect) gain.connect(ctx.destination);

        gainRef.current = gain;
        setSourceNode(gain);
        setIsReady(true);

        const samples = new Float32Array(analyser.fftSize);
        meterTimer = setInterval(() => {
          if (cancelled) return;
          analyser.getFloatTimeDomainData(samples);
          let sum = 0;
          for (let i = 0; i < samples.length; i++) sum += samples[i] * samples[i];
          const rms = Math.sqrt(sum / samples.length);
          setAudioLevel(Math.min(1, rms * 3));
        }, 100);

        openSocket();
      })
      .catch((err) => {
        logger.error('PCM worklet load failed', { instanceId, error: err?.message });
      });

    return () => {
      cancelled = true;
      if (reconnectTimer) clearTimeout(reconnectTimer);
      if (meterTimer) clearInterval(meterTimer);
      if (ws) {
        ws.onclose = null; // no reconnect out of a deliberate teardown
        try { ws.close(); } catch { /* already closed */ }
      }
      if (workletNode) {
        workletNode.port.onmessage = null;
        try { workletNode.disconnect(); } catch { /* detached */ }
      }
      if (analyser) { try { analyser.disconnect(); } catch { /* detached */ } }
      if (gain) { try { gain.disconnect(); } catch { /* detached */ } }
      if (ownsCtx && ctx.state !== 'closed') ctx.close();
      ctxRef.current = null;
      gainRef.current = null;
      setSourceNode(null);
      setIsReady(false);
      setAudioLevel(0);
    };
  }, [instanceId, sharedCtx, enabled, createContext, connect]);

  const setVolume = useCallback((v) => {
    const gain = gainRef.current;
    const ctx = ctxRef.current;
    if (!gain || !ctx) return;
    gain.gain.linearRampToValueAtTime(v, ctx.currentTime + 0.05);
  }, []);

  const resume = useCallback(async () => {
    const ctx = ctxRef.current;
    if (ctx && ctx.state === 'suspended') await ctx.resume();
  }, []);

  return { sourceNode, gainNode: sourceNode, audioLevel, isReady, setVolume, resume };
}
