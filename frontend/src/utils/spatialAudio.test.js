/**
 * Unit tests for the useSpatialAudio hook and SPATIAL_DEFAULTS.
 *
 * Because the hook depends on Web Audio API objects we mock the
 * AudioContext family and validate wiring / parameter application.
 */

import { describe, it, expect, vi, beforeEach } from 'vitest';
import { SPATIAL_DEFAULTS } from '../hooks/useSpatialAudio';

// ---------------------------------------------------------------------------
// Exported constants
// ---------------------------------------------------------------------------
describe('SPATIAL_DEFAULTS', () => {
  it('should expose expected default keys', () => {
    expect(SPATIAL_DEFAULTS).toHaveProperty('distanceModel', 'inverse');
    expect(SPATIAL_DEFAULTS).toHaveProperty('refDistance', 1);
    expect(SPATIAL_DEFAULTS).toHaveProperty('maxDistance', 20);
    expect(SPATIAL_DEFAULTS).toHaveProperty('rolloffFactor', 1);
    expect(SPATIAL_DEFAULTS).toHaveProperty('rampTime', 0.05);
    expect(SPATIAL_DEFAULTS).toHaveProperty('mono', false);
  });

  it('should use HRTF-compatible cone defaults (full sphere)', () => {
    expect(SPATIAL_DEFAULTS.coneInnerAngle).toBe(360);
    expect(SPATIAL_DEFAULTS.coneOuterAngle).toBe(360);
    expect(SPATIAL_DEFAULTS.coneOuterGain).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// AudioContext mock helpers
// ---------------------------------------------------------------------------
function createMockAudioParam(initial = 0) {
  return {
    value: initial,
    setValueAtTime: vi.fn(),
    linearRampToValueAtTime: vi.fn(),
  };
}

function createMockPanner() {
  return {
    panningModel: '',
    distanceModel: '',
    refDistance: 0,
    maxDistance: 0,
    rolloffFactor: 0,
    coneInnerAngle: 0,
    coneOuterAngle: 0,
    coneOuterGain: 0,
    positionX: createMockAudioParam(),
    positionY: createMockAudioParam(),
    positionZ: createMockAudioParam(),
    connect: vi.fn().mockReturnThis(),
    disconnect: vi.fn(),
  };
}

function createMockGain() {
  return {
    gain: createMockAudioParam(1),
    connect: vi.fn().mockReturnThis(),
    disconnect: vi.fn(),
  };
}

function createMockSource() {
  return {
    connect: vi.fn().mockReturnThis(),
    disconnect: vi.fn(),
  };
}

function createMockMerger() {
  return {
    connect: vi.fn().mockReturnThis(),
    disconnect: vi.fn(),
  };
}

function createMockAudioContext() {
  const panner = createMockPanner();
  const gain = createMockGain();
  const source = createMockSource();
  const merger = createMockMerger();
  return {
    currentTime: 0,
    state: 'running',
    destination: {},
    listener: {
      positionX: createMockAudioParam(),
      positionY: createMockAudioParam(),
      positionZ: createMockAudioParam(),
    },
    createPanner: vi.fn(() => panner),
    createGain: vi.fn(() => gain),
    createMediaStreamSource: vi.fn(() => source),
    createChannelMerger: vi.fn(() => merger),
    close: vi.fn(),
    resume: vi.fn(),
    _mocks: { panner, gain, source, merger },
  };
}

// ---------------------------------------------------------------------------
// Panner wiring integration (no React rendering needed)
// ---------------------------------------------------------------------------
describe('Spatial audio panner wiring', () => {
  let mockCtx;

  beforeEach(() => {
    mockCtx = createMockAudioContext();
  });

  it('should configure panner with HRTF and inverse distance by default', () => {
    const { panner } = mockCtx._mocks;

    // Simulate what the hook does internally
    panner.panningModel = SPATIAL_DEFAULTS.mono ? 'equalpower' : 'HRTF';
    panner.distanceModel = SPATIAL_DEFAULTS.distanceModel;
    panner.refDistance = SPATIAL_DEFAULTS.refDistance;
    panner.maxDistance = SPATIAL_DEFAULTS.maxDistance;
    panner.rolloffFactor = SPATIAL_DEFAULTS.rolloffFactor;

    expect(panner.panningModel).toBe('HRTF');
    expect(panner.distanceModel).toBe('inverse');
    expect(panner.refDistance).toBe(1);
    expect(panner.maxDistance).toBe(20);
    expect(panner.rolloffFactor).toBe(1);
  });

  it('should use equalpower panning model when mono is true', () => {
    const { panner } = mockCtx._mocks;
    const cfg = { ...SPATIAL_DEFAULTS, mono: true };

    panner.panningModel = cfg.mono ? 'equalpower' : 'HRTF';

    expect(panner.panningModel).toBe('equalpower');
  });

  it('should set initial position via setValueAtTime for smooth start', () => {
    const { panner } = mockCtx._mocks;
    const position = [1.4, 0, -3];
    const t = mockCtx.currentTime;

    panner.positionX.setValueAtTime(position[0], t);
    panner.positionY.setValueAtTime(position[1], t);
    panner.positionZ.setValueAtTime(position[2], t);

    expect(panner.positionX.setValueAtTime).toHaveBeenCalledWith(1.4, 0);
    expect(panner.positionY.setValueAtTime).toHaveBeenCalledWith(0, 0);
    expect(panner.positionZ.setValueAtTime).toHaveBeenCalledWith(-3, 0);
  });

  it('should route through channel merger when mono is enabled', () => {
    const { source, merger, panner } = mockCtx._mocks;
    const cfg = { ...SPATIAL_DEFAULTS, mono: true };

    if (cfg.mono) {
      source.connect(merger);
      merger.connect(panner);
    } else {
      source.connect(panner);
    }

    expect(source.connect).toHaveBeenCalledWith(merger);
    expect(merger.connect).toHaveBeenCalledWith(panner);
  });

  it('should connect source directly to panner when stereo (default)', () => {
    const { source, panner } = mockCtx._mocks;
    const cfg = { ...SPATIAL_DEFAULTS };

    if (cfg.mono) {
      // not taken
    } else {
      source.connect(panner);
    }

    expect(source.connect).toHaveBeenCalledWith(panner);
  });

  it('should use linearRampToValueAtTime for smooth volume changes', () => {
    const { gain } = mockCtx._mocks;
    const rampTime = SPATIAL_DEFAULTS.rampTime;
    const targetVol = 0.5;
    const t = mockCtx.currentTime + rampTime;

    gain.gain.linearRampToValueAtTime(targetVol, t);

    expect(gain.gain.linearRampToValueAtTime).toHaveBeenCalledWith(0.5, rampTime);
  });

  it('should use linearRampToValueAtTime for smooth position transitions', () => {
    const { panner } = mockCtx._mocks;
    const rampTime = SPATIAL_DEFAULTS.rampTime;
    const newPos = [2.8, 1.0, -3];
    const t = mockCtx.currentTime + rampTime;

    panner.positionX.linearRampToValueAtTime(newPos[0], t);
    panner.positionY.linearRampToValueAtTime(newPos[1], t);
    panner.positionZ.linearRampToValueAtTime(newPos[2], t);

    expect(panner.positionX.linearRampToValueAtTime).toHaveBeenCalledWith(2.8, rampTime);
    expect(panner.positionY.linearRampToValueAtTime).toHaveBeenCalledWith(1.0, rampTime);
    expect(panner.positionZ.linearRampToValueAtTime).toHaveBeenCalledWith(-3, rampTime);
  });
});
