import { useEffect, useRef } from 'react';

// Hook that positions audio in 3D space and exposes a volume setter
export default function useSpatialAudio(videoRef, position = [0,0,-3]) {
  const ctxRef = useRef(null);
  const gainRef = useRef(null);
  const pannerRef = useRef(null);
  const sourceRef = useRef(null);

  useEffect(() => {
    let interval;
    function setup() {
      const vid = videoRef.current;
      if (!vid || !vid.srcObject || ctxRef.current) return;
      const ctx = new (window.AudioContext || window.webkitAudioContext)();
      ctxRef.current = ctx;
      const src = ctx.createMediaStreamSource(vid.srcObject);
      sourceRef.current = src;
      const panner = ctx.createPanner();
      panner.panningModel = 'HRTF';
      panner.positionX.value = position[0];
      panner.positionY.value = position[1];
      panner.positionZ.value = position[2];
      const gain = ctx.createGain();
      gain.gain.value = 1;
      src.connect(panner).connect(gain).connect(ctx.destination);
      gainRef.current = gain;
      pannerRef.current = panner;
    }
    interval = setInterval(setup, 500);
    setup();
    return () => {
      clearInterval(interval);
      if (sourceRef.current) sourceRef.current.disconnect();
      if (gainRef.current) gainRef.current.disconnect();
      if (ctxRef.current) ctxRef.current.close();
      ctxRef.current = null;
      gainRef.current = null;
      pannerRef.current = null;
      sourceRef.current = null;
    };
  }, [videoRef, position[0], position[1], position[2]]);

  const setVolume = (v) => {
    if (gainRef.current) gainRef.current.gain.value = v;
  };

  const setPosition = (pos) => {
    if (pannerRef.current) {
      pannerRef.current.positionX.value = pos[0];
      pannerRef.current.positionY.value = pos[1];
      pannerRef.current.positionZ.value = pos[2];
    }
  };

  return { setVolume, setPosition };
}
