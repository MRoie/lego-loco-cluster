import { useEffect, useRef } from 'react';

/**
 * Keeps the Web Audio API listener in sync with the A-Frame camera rig
 * so that spatial audio sources are perceived relative to the user's
 * head position and orientation in VR.
 *
 * @param {AudioContext|null} ctx - shared AudioContext (may be null before init)
 * @param {string} [rigSelector='#rig'] - CSS selector for the A-Frame camera rig entity
 * @param {number} [intervalMs=100] - how often to poll the rig position (ms)
 */
export default function useVRAudioListener(ctx, rigSelector = '#rig', intervalMs = 100) {
  const timerRef = useRef(null);

  useEffect(() => {
    if (!ctx) return;

    function sync() {
      const rig = document.querySelector(rigSelector);
      if (!rig || !rig.object3D) return;

      const pos = rig.object3D.position;
      const listener = ctx.listener;

      // Prefer the AudioParam-based API (modern browsers)
      if (listener.positionX) {
        const t = ctx.currentTime + 0.05;
        listener.positionX.linearRampToValueAtTime(pos.x, t);
        listener.positionY.linearRampToValueAtTime(pos.y, t);
        listener.positionZ.linearRampToValueAtTime(pos.z, t);
      } else if (typeof listener.setPosition === 'function') {
        listener.setPosition(pos.x, pos.y, pos.z);
      }

      // Orientation: A-Frame stores rotation as Euler in degrees.
      // We derive a forward and up vector from the camera's world quaternion.
      const cam = rig.querySelector('[camera]');
      if (cam && cam.object3D) {
        const q = cam.object3D.quaternion;
        // Forward vector (-Z in WebGL)
        const fx = 2 * (q.x * q.z + q.w * q.y);
        const fy = 2 * (q.y * q.z - q.w * q.x);
        const fz = 1 - 2 * (q.x * q.x + q.y * q.y);
        // Up vector (+Y)
        const ux = 2 * (q.x * q.y - q.w * q.z);
        const uy = 1 - 2 * (q.x * q.x + q.z * q.z);
        const uz = 2 * (q.y * q.z + q.w * q.x);

        if (listener.forwardX) {
          const t = ctx.currentTime + 0.05;
          listener.forwardX.linearRampToValueAtTime(fx, t);
          listener.forwardY.linearRampToValueAtTime(fy, t);
          listener.forwardZ.linearRampToValueAtTime(fz, t);
          listener.upX.linearRampToValueAtTime(ux, t);
          listener.upY.linearRampToValueAtTime(uy, t);
          listener.upZ.linearRampToValueAtTime(uz, t);
        } else if (typeof listener.setOrientation === 'function') {
          listener.setOrientation(fx, fy, fz, ux, uy, uz);
        }
      }
    }

    timerRef.current = setInterval(sync, intervalMs);
    sync();

    return () => {
      if (timerRef.current) clearInterval(timerRef.current);
    };
  }, [ctx, rigSelector, intervalMs]);
}
