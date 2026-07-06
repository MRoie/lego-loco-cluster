import { useEffect, useRef, useState, useCallback } from 'react';
import { createLogger } from '../utils/logger';

const logger = createLogger('useAdaptiveStreaming');

const DEFAULT_THRESHOLDS = {
  packetLossReduceFps: 5,       // % — reduce framerate when packet loss exceeds this
  packetLossReduceRes: 10,      // % — reduce resolution when packet loss exceeds this
  packetLossRestore: 2,         // % — restore quality when loss drops below this
  restoreHoldSeconds: 30,       // seconds of good quality before restoring
};

const QUALITY_PRESETS = {
  full: { maxFramerate: 30, scaleResolutionDownBy: 1.0, label: 'Full' },
  reducedFps: { maxFramerate: 15, scaleResolutionDownBy: 1.0, label: 'Reduced FPS' },
  reducedAll: { maxFramerate: 15, scaleResolutionDownBy: 2.0, label: 'Reduced FPS + Resolution' },
};

/**
 * Adaptive streaming hook that monitors WebRTC stats and adjusts
 * encoding parameters when network conditions degrade.
 *
 * @param {RTCPeerConnection|null} peerConnection - active peer connection
 * @param {object} stats - connectionQuality from useWebRTC
 * @returns {{ currentQuality: object, isAdapting: boolean, thresholds: object }}
 */
export default function useAdaptiveStreaming(peerConnection, stats) {
  const [currentQuality, setCurrentQuality] = useState(QUALITY_PRESETS.full);
  const [isAdapting, setIsAdapting] = useState(false);
  const [thresholds] = useState(DEFAULT_THRESHOLDS);

  // Track how long packet loss has been below the restore threshold
  const goodSinceRef = useRef(null);
  const currentPresetRef = useRef('full');

  const applyEncodingParams = useCallback(async (preset) => {
    if (!peerConnection) return;

    const senders = peerConnection.getSenders();
    for (const sender of senders) {
      if (sender.track?.kind !== 'video') continue;

      const params = sender.getParameters();
      if (!params.encodings || params.encodings.length === 0) continue;

      for (const encoding of params.encodings) {
        encoding.maxFramerate = preset.maxFramerate;
        encoding.scaleResolutionDownBy = preset.scaleResolutionDownBy;
      }

      try {
        await sender.setParameters(params);
        logger.info('Applied encoding parameters', { preset: preset.label });
      } catch (err) {
        logger.warn('Failed to apply encoding parameters', { error: err.message });
      }
    }
  }, [peerConnection]);

  useEffect(() => {
    if (!stats) return;

    const { packetLoss } = stats;
    const now = Date.now();

    if (packetLoss > thresholds.packetLossReduceRes) {
      // Severe degradation — reduce both FPS and resolution
      goodSinceRef.current = null;
      if (currentPresetRef.current !== 'reducedAll') {
        currentPresetRef.current = 'reducedAll';
        setCurrentQuality(QUALITY_PRESETS.reducedAll);
        setIsAdapting(true);
        applyEncodingParams(QUALITY_PRESETS.reducedAll);
        logger.info('Severe packet loss — reducing FPS + resolution', { packetLoss });
      }
    } else if (packetLoss > thresholds.packetLossReduceFps) {
      // Moderate degradation — reduce framerate only
      goodSinceRef.current = null;
      if (currentPresetRef.current !== 'reducedFps') {
        currentPresetRef.current = 'reducedFps';
        setCurrentQuality(QUALITY_PRESETS.reducedFps);
        setIsAdapting(true);
        applyEncodingParams(QUALITY_PRESETS.reducedFps);
        logger.info('Moderate packet loss — reducing FPS', { packetLoss });
      }
    } else if (packetLoss < thresholds.packetLossRestore) {
      // Good conditions — restore after hold period
      if (!goodSinceRef.current) {
        goodSinceRef.current = now;
      }
      const goodDuration = (now - goodSinceRef.current) / 1000;
      if (goodDuration >= thresholds.restoreHoldSeconds && currentPresetRef.current !== 'full') {
        currentPresetRef.current = 'full';
        setCurrentQuality(QUALITY_PRESETS.full);
        setIsAdapting(false);
        applyEncodingParams(QUALITY_PRESETS.full);
        logger.info('Network recovered — restoring full quality', { packetLoss, goodDuration });
      }
    } else {
      // Between restore and reduce thresholds — hold current state
      goodSinceRef.current = null;
    }
  }, [stats, thresholds, applyEncodingParams]);

  return { currentQuality, isAdapting, thresholds };
}
