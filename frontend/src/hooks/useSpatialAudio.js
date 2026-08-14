import { useEffect, useRef, useState, useCallback } from 'react';

/**
 * Default spatial audio configuration.
 * distanceModel / rolloffFactor control how volume falls off with distance.
 * rampTime controls the smoothness of position and volume transitions.
 * mono forces a single-channel downmix for accessibility.
 */
export const SPATIAL_DEFAULTS = {
  distanceModel: 'inverse',
  refDistance: 1,
  maxDistance: 20,
  rolloffFactor: 1,
  coneInnerAngle: 360,
  coneOuterAngle: 360,
  coneOuterGain: 0,
  rampTime: 0.05,
  mono: false,
};

/**
 * Hook that positions audio from a media element in 3D space using
 * Web Audio HRTF panning.  Supports smooth transitions, configurable
 * distance model and an accessible mono fallback.
 *
 * @param {React.RefObject} videoRef - ref to the <video> / <audio> element
 * @param {number[]} position - [x, y, z] initial position
 * @param {object} [options] - override any key from SPATIAL_DEFAULTS; pass
 *   options.sourceNode (any AudioNode, e.g. usePCMAudio's gain) to spatialise
 *   an existing Web Audio node instead of tapping a media element
 * @param {AudioContext} [sharedCtx] - optional shared AudioContext
 */
export default function useSpatialAudio(
  videoRef,
  position = [0, 0, -3],
  options = {},
  sharedCtx = null,
) {
  const mono = !!(options.mono ?? SPATIAL_DEFAULTS.mono);
  const cfg = { ...SPATIAL_DEFAULTS, ...options, mono };
  const sourceNode = options.sourceNode || null;
  const ctxRef = useRef(null);
  const gainRef = useRef(null);
  const pannerRef = useRef(null);
  const sourceRef = useRef(null);
  // First node downstream of an external sourceNode (merger or panner). Kept
  // so teardown can detach just this edge — a blanket disconnect() would also
  // sever connections the node's owner made (e.g. a flat destination path).
  const externalHeadRef = useRef(null);
  const ownsCtx = useRef(false);
  const [isReady, setIsReady] = useState(false);

  useEffect(() => {
    let interval;
    function setup() {
      if (ctxRef.current) return;

      let ctx, src;
      if (sourceNode) {
        // An existing Web Audio node (the PCM worklet path). No media element
        // to poll for, and the node dictates the context — Web Audio nodes
        // cannot connect across contexts.
        ctx = sourceNode.context;
        ownsCtx.current = false;
        src = sourceNode;
      } else {
        const vid = videoRef.current;
        if (!vid || !vid.srcObject) return;

        ctx =
          sharedCtx || new (window.AudioContext || window.webkitAudioContext)();
        ownsCtx.current = !sharedCtx;
        src = ctx.createMediaStreamSource(vid.srcObject);
      }
      ctxRef.current = ctx;
      sourceRef.current = src;

      // Choose panning model: 'equalpower' for mono fallback, 'HRTF' for 3D
      const panner = ctx.createPanner();
      panner.panningModel = cfg.mono ? 'equalpower' : 'HRTF';
      panner.distanceModel = cfg.distanceModel;
      panner.refDistance = cfg.refDistance;
      panner.maxDistance = cfg.maxDistance;
      panner.rolloffFactor = cfg.rolloffFactor;
      panner.coneInnerAngle = cfg.coneInnerAngle;
      panner.coneOuterAngle = cfg.coneOuterAngle;
      panner.coneOuterGain = cfg.coneOuterGain;

      // Set initial position smoothly
      const t = ctx.currentTime;
      panner.positionX.setValueAtTime(position[0], t);
      panner.positionY.setValueAtTime(position[1], t);
      panner.positionZ.setValueAtTime(position[2], t);

      const gain = ctx.createGain();
      gain.gain.setValueAtTime(1, t);

      // Mono downmix for accessibility: force single channel before panner
      if (cfg.mono) {
        const merger = ctx.createChannelMerger(1);
        src.connect(merger);
        merger.connect(panner);
        externalHeadRef.current = merger;
      } else {
        src.connect(panner);
        externalHeadRef.current = panner;
      }
      panner.connect(gain).connect(ctx.destination);

      gainRef.current = gain;
      pannerRef.current = panner;
      setIsReady(true);
      clearInterval(interval);
    }
    if (sourceNode) {
      // The node is already live — no srcObject to wait for.
      setup();
    } else {
      interval = setInterval(setup, 500);
      setup();
    }
    return () => {
      clearInterval(interval);
      if (sourceRef.current) {
        if (sourceNode && externalHeadRef.current) {
          // Detach only our edge; the node's owner keeps its other routes.
          try { sourceRef.current.disconnect(externalHeadRef.current); } catch { /* already detached */ }
        } else {
          sourceRef.current.disconnect();
        }
      }
      if (gainRef.current) gainRef.current.disconnect();
      if (pannerRef.current) pannerRef.current.disconnect();
      if (ownsCtx.current && ctxRef.current) ctxRef.current.close();
      ctxRef.current = null;
      gainRef.current = null;
      pannerRef.current = null;
      sourceRef.current = null;
      externalHeadRef.current = null;
      ownsCtx.current = false;
      setIsReady(false);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [videoRef, position[0], position[1], position[2], mono, sharedCtx, sourceNode]);

  /** Smoothly ramp volume to the target value. */
  const setVolume = useCallback(
    (v) => {
      const gain = gainRef.current;
      const ctx = ctxRef.current;
      if (!gain || !ctx) return;
      gain.gain.linearRampToValueAtTime(v, ctx.currentTime + cfg.rampTime);
    },
    [cfg.rampTime],
  );

  /** Smoothly ramp the panner to a new [x,y,z] position. */
  const setPosition = useCallback(
    (pos) => {
      const panner = pannerRef.current;
      const ctx = ctxRef.current;
      if (!panner || !ctx) return;
      const t = ctx.currentTime + cfg.rampTime;
      panner.positionX.linearRampToValueAtTime(pos[0], t);
      panner.positionY.linearRampToValueAtTime(pos[1], t);
      panner.positionZ.linearRampToValueAtTime(pos[2], t);
    },
    [cfg.rampTime],
  );

  /** Resume a suspended AudioContext (handles browser autoplay policy). */
  const resumeContext = useCallback(async () => {
    const ctx = ctxRef.current;
    if (ctx && ctx.state === 'suspended') {
      await ctx.resume();
    }
  }, []);

  return { setVolume, setPosition, resumeContext, isReady };
}
