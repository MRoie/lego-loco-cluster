import { useRef, useCallback, useState } from 'react';

/**
 * Records spatial-audio performance metrics during a VR session.
 *
 * Captured data per sample (sampled every `intervalMs`):
 *  - timestamp (ISO-8601)
 *  - audioContextTime (seconds from AudioContext.currentTime)
 *  - listenerPosition {x,y,z}
 *  - activeTile index
 *  - perTile[] – volume, pannerPosition {x,y,z}, audioLatencyMs
 *  - mono flag
 *  - audioContextState ('running' | 'suspended' | 'closed')
 *
 * The recording can be exported as a JSON file for offline analysis and
 * attached to PRs as a performance log artifact.
 */
export default function usePerformanceRecorder(intervalMs = 200) {
  const samplesRef = useRef([]);
  const timerRef = useRef(null);
  const startTimeRef = useRef(null);
  const [recording, setRecording] = useState(false);

  /**
   * Start recording.
   * @param {AudioContext} ctx       – shared AudioContext
   * @param {string}       rigSelector – CSS selector for the A-Frame rig
   */
  const startRecording = useCallback(
    (ctx, rigSelector = '#rig') => {
      if (timerRef.current) return; // already recording
      samplesRef.current = [];
      startTimeRef.current = Date.now();
      setRecording(true);

      function sample() {
        const now = new Date();
        const entry = {
          timestamp: now.toISOString(),
          elapsedMs: Date.now() - startTimeRef.current,
          audioContextTime: ctx ? ctx.currentTime : null,
          audioContextState: ctx ? ctx.state : 'unavailable',
          listenerPosition: null,
          listenerOrientation: null,
          activeTile: null,
          mono: null,
          tiles: [],
        };

        // Listener position from AudioContext
        if (ctx && ctx.listener) {
          const l = ctx.listener;
          if (l.positionX) {
            entry.listenerPosition = {
              x: l.positionX.value,
              y: l.positionY.value,
              z: l.positionZ.value,
            };
          }
          if (l.forwardX) {
            entry.listenerOrientation = {
              forwardX: l.forwardX.value,
              forwardY: l.forwardY.value,
              forwardZ: l.forwardZ.value,
              upX: l.upX.value,
              upY: l.upY.value,
              upZ: l.upZ.value,
            };
          }
        }

        // Camera rig position from A-Frame
        const rig = document.querySelector(rigSelector);
        if (rig && rig.object3D) {
          const pos = rig.object3D.position;
          entry.rigPosition = { x: pos.x, y: pos.y, z: pos.z };
        }

        // Estimate audio output latency when available
        if (ctx && typeof ctx.outputLatency === 'number') {
          entry.outputLatencyMs = Math.round(ctx.outputLatency * 1000 * 100) / 100;
        } else if (ctx && ctx.baseLatency) {
          entry.outputLatencyMs = Math.round(ctx.baseLatency * 1000 * 100) / 100;
        }

        samplesRef.current.push(entry);
      }

      timerRef.current = setInterval(sample, intervalMs);
      sample(); // initial sample
    },
    [intervalMs],
  );

  /** Enrich the latest sample with per-tile data (called from VRScene). */
  const recordTileSnapshot = useCallback(
    (activeTile, mono, tileData) => {
      const samples = samplesRef.current;
      if (!samples.length) return;
      const last = samples[samples.length - 1];
      last.activeTile = activeTile;
      last.mono = mono;
      last.tiles = tileData; // [{id, volume, position:{x,y,z}}]
    },
    [],
  );

  /** Stop recording and return the samples array. */
  const stopRecording = useCallback(() => {
    if (timerRef.current) {
      clearInterval(timerRef.current);
      timerRef.current = null;
    }
    setRecording(false);
    return samplesRef.current;
  }, []);

  /** Build a downloadable JSON blob and trigger a browser download. */
  const exportRecording = useCallback(() => {
    const data = stopRecording();
    const summary = buildSummary(data);
    const payload = {
      version: 1,
      exportedAt: new Date().toISOString(),
      sampleCount: data.length,
      durationMs: data.length > 0 ? data[data.length - 1].elapsedMs : 0,
      summary,
      samples: data,
    };

    const blob = new Blob([JSON.stringify(payload, null, 2)], {
      type: 'application/json',
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `vr-audio-perf-${Date.now()}.json`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
    return payload;
  }, [stopRecording]);

  return { recording, startRecording, stopRecording, recordTileSnapshot, exportRecording };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Derive summary statistics from the raw samples array. */
function buildSummary(samples) {
  if (!samples.length) return {};

  const latencies = samples
    .map((s) => s.outputLatencyMs)
    .filter((v) => v != null);

  const sorted = [...latencies].sort((a, b) => a - b);

  return {
    totalSamples: samples.length,
    durationMs: samples[samples.length - 1].elapsedMs,
    audioLatency: latencies.length
      ? {
          min: sorted[0],
          max: sorted[sorted.length - 1],
          avg: Math.round((sorted.reduce((a, b) => a + b, 0) / sorted.length) * 100) / 100,
          p50: percentile(sorted, 0.5),
          p95: percentile(sorted, 0.95),
          p99: percentile(sorted, 0.99),
        }
      : null,
    monoUsed: samples.some((s) => s.mono === true),
    contextStates: [...new Set(samples.map((s) => s.audioContextState))],
  };
}

function percentile(sorted, p) {
  if (!sorted.length) return 0;
  const idx = Math.min(Math.floor(sorted.length * p), sorted.length - 1);
  return sorted[idx];
}
