import 'aframe';
import React, { useEffect, useState, useRef, useCallback } from 'react';
import { useActive } from './ActiveContext';
import useWebRTC from './hooks/useWebRTC';
import useSpatialAudio from './hooks/useSpatialAudio';
import usePCMAudio from './hooks/usePCMAudio';
import useVRAudioListener from './hooks/useVRAudioListener';
import usePerformanceRecorder from './hooks/usePerformanceRecorder';
import useVideoRecorder from './hooks/useVideoRecorder';
import { FORMAT_KEYS, EXPORT_FORMATS } from './utils/mediaExport';
import VRNoVNCViewer from './components/VRNoVNCViewer';
import ControlsConfig from './components/ControlsConfig';
import VRToast from './components/VRToast';

/* The controller-to-guest pointer, as one A-Frame component on the entity that
 * owns the raycaster.
 *
 * Design rules, each earned the hard way:
 *  - ONLY discrete edge events set buttons. A-Frame's cursor `click` requires
 *    the analog trigger to cross a driver-defined threshold with down and up
 *    on the same entity, which is exactly the "inconsistent full click" the
 *    headset user reported. triggerdown/triggerup are unambiguous edges.
 *  - One button mask, owned here. Left = trigger (RFB bit 0x1), right = grip
 *    or B (bit 0x4), wheel = thumbstick pulses (bits 0x8/0x10). The guest
 *    needs right-click; nothing else in the scene may repurpose these events.
 *  - A release is delivered even if the ray has left the tile, at the last
 *    known position — otherwise a press-move-release off the edge leaves the
 *    guest with a stuck button.
 *  - Hover streams continuously (~30 Hz) with the current mask, so the guest
 *    cursor tracks the laser and press-move-release is a drag.
 * The component only computes UV; the tile maps UV to framebuffer pixels,
 * because only the tile knows its canvas.
 */
const VNC_LASER_RESERVED = [
  'triggerdown', 'triggerup', 'gripdown', 'gripup',
  'bbuttondown', 'bbuttonup', 'pinchstarted', 'pinchended',
];

if (typeof window !== 'undefined' && window.AFRAME &&
    !window.AFRAME.components['vnc-canvas-refresh']) {
  // noVNC repaints its canvas; THREE re-uploads only when told. A component
  // tick runs inside A-Frame's render loop, which follows the XR session's
  // frame clock in immersive mode — a window rAF loop does not.
  window.AFRAME.registerComponent('vnc-canvas-refresh', {
    tick() {
      if (this.el.vncTexture) this.el.vncTexture.needsUpdate = true;
    },
  });
}

if (typeof window !== 'undefined' && window.AFRAME &&
    !window.AFRAME.components['vnc-laser-input']) {
  window.AFRAME.registerComponent('vnc-laser-input', {
    init() {
      this.mask = 0;
      this.lastEl = null;
      this.lastUV = null;
      this.wheelArmed = true;
      this.wheelTimer = null;
      this.tick = window.AFRAME.utils.throttleTick(this.hoverTick, 33, this);

      this.handlers = {
        triggerdown: () => this.setBit(0x1, true),
        triggerup: () => this.setBit(0x1, false),
        pinchstarted: () => this.setBit(0x1, true),
        pinchended: () => this.setBit(0x1, false),
        gripdown: () => this.setBit(0x4, true),
        gripup: () => this.setBit(0x4, false),
        bbuttondown: () => this.setBit(0x4, true),
        bbuttonup: () => this.setBit(0x4, false),
        thumbstickmoved: (e) => this.wheel(e.detail && e.detail.y),
      };
      Object.entries(this.handlers).forEach(([ev, fn]) =>
        this.el.addEventListener(ev, fn));
    },

    remove() {
      Object.entries(this.handlers).forEach(([ev, fn]) =>
        this.el.removeEventListener(ev, fn));
      if (this.wheelTimer) clearTimeout(this.wheelTimer);
    },

    intersection() {
      const rc = this.el.components.raycaster;
      const hit = rc && rc.intersections && rc.intersections[0];
      return (hit && hit.uv && hit.object && hit.object.el) ? hit : null;
    },

    setBit(bit, on) {
      const next = on ? (this.mask | bit) : (this.mask & ~bit);
      if (next === this.mask) return;
      this.mask = next;
      this.emitPointer(on);
    },

    // RFB wheel = a momentary press of button 4 (up) or 5 (down). Pulse the
    // bit and restore, edge-triggered with hysteresis so one flick is one
    // notch, auto-repeating while held hard over.
    wheel(y) {
      if (typeof y !== 'number') return;
      const mag = Math.abs(y);
      if (mag < 0.3) {
        this.wheelArmed = true;
        if (this.wheelTimer) { clearTimeout(this.wheelTimer); this.wheelTimer = null; }
        return;
      }
      if (mag < 0.6 || !this.wheelArmed) return;
      this.wheelArmed = false;
      const bit = y < 0 ? 0x8 : 0x10;
      const base = this.mask;
      this.mask = base | bit;
      this.emitPointer(true);
      this.mask = base;
      this.emitPointer(false);
      this.wheelTimer = setTimeout(() => { this.wheelArmed = true; this.wheel(y); }, 150);
    },

    emitPointer(pressedEdge) {
      const hit = this.intersection();
      let el = this.lastEl;
      let uv = this.lastUV;
      if (hit) {
        el = hit.object.el;
        uv = { x: hit.uv.x, y: hit.uv.y };
        this.lastEl = el;
        this.lastUV = uv;
      }
      if (!el || !uv) return;
      el.dispatchEvent(new CustomEvent('vnc-pointer', {
        detail: { u: uv.x, v: uv.y, mask: this.mask,
                  pressed: !!pressedEdge && this.mask !== 0 },
      }));
    },

    hoverTick() {
      const hit = this.intersection();
      if (!hit) return;
      const uv = hit.uv;
      const moved = hit.object.el !== this.lastEl || !this.lastUV ||
        Math.abs(uv.x - this.lastUV.x) > 0.001 ||
        Math.abs(uv.y - this.lastUV.y) > 0.001;
      if (moved) this.emitPointer(false);
    },
  });
}

function positionForIndex(i, cols, rows) {
  const x = (i % cols) - (cols - 1) / 2;
  const row = Math.floor(i / cols);
  const y = (rows - 1) / 2 - row;
  // Positions are RELATIVE to the tile wall entity, which itself sits at
  // standing eye height — so scaling the wall expands it around the centre
  // of view instead of lifting it off the floor. Spacing leaves room for the
  // active tile's pop-out without overlap, including in the 2x2 layout four
  // instances produce.
  return { x: x * 1.55, y: y * 1.15 };
}

function VRTile({ inst, idx, active, setActive, setActiveIds, cols, rows, status, onVNCReady, volume, ambientVolume, activeIds, sharedAudioCtx, monoAudio, muted, audioLevel, onAudioLevel, wallZ }) {
  const vncRef = useRef(null);
  const planeRef = useRef(null);
  const textureRef = useRef(null);
  const [textureCreated, setTextureCreated] = useState(false);

  // Texture refresh lives in an A-Frame component tick (see
  // vnc-canvas-refresh below), NOT a window requestAnimationFrame loop:
  // window rAF stops firing inside an immersive XR session — rendering moves
  // to the session's own clock — so a rAF-driven refresh freezes the moment
  // the headset takes over. That was "video stuck in VR, fluid on the web".
  const { videoRef: rtcVideoRef, audioLevel: tileAudioLevel } = useWebRTC(inst.id);
  const pos = positionForIndex(idx, cols, rows);
  // Guest audio: raw PCM over /proxy/audio/<id>/ into an AudioWorklet.
  // createContext: false — all tiles must share VRScene's one AudioContext
  // (the VR listener is synced to it), so wait for it instead of making one.
  const pcm = usePCMAudio(inst.id, sharedAudioCtx, { createContext: false });
  // While pcm.sourceNode is null useSpatialAudio falls back to its videoRef
  // (WebRTC) path, so tiles keep sounding exactly as before until the PCM
  // stream is live; the effect rebuilds onto the worklet source when it is.
  const { setVolume, resumeContext } = useSpatialAudio(
    rtcVideoRef,
    [pos.x, pos.y + 1.5, wallZ],
    { mono: monoAudio, sourceNode: pcm.sourceNode },
    sharedAudioCtx,
  );
  // PCM meter once the guest-audio path is live, WebRTC's meter otherwise.
  const liveAudioLevel = pcm.isReady ? pcm.audioLevel : tileAudioLevel;

  // Propagate audio level up to parent for per-tile meters
  useEffect(() => {
    if (onAudioLevel) onAudioLevel(idx, liveAudioLevel);
  }, [liveAudioLevel, idx, onAudioLevel]);


  useEffect(() => {
    if (muted) {
      setVolume(0);
      return;
    }
    const finalVol = volume * (activeIds.includes(inst.id) ? 1 : ambientVolume);
    setVolume(finalVol);
  }, [volume, activeIds, inst.id, ambientVolume, setVolume, muted]);

  const handleVNCConnect = (instanceId) => {
    console.log(`VR: VNC connected for ${instanceId}`);
    
    // Texture the tile straight from noVNC's canvas. The old code pushed the
    // canvas through <a-asset-item src={canvas}> — setting a DOM object as an
    // attribute stringifies it to "[object HTMLCanvasElement]", so the
    // material src pointed at nothing and every tile rendered black. THREE
    // takes a canvas directly.
    const canvas = vncRef.current?.getCanvas();
    if (canvas && planeRef.current) {
      const plane = planeRef.current;
      const THREE = window.AFRAME && window.AFRAME.THREE;
      const applyTexture = () => {
        const mesh = plane.getObject3D && plane.getObject3D('mesh');
        if (!mesh || !THREE) {
          // A-Frame may not have built the mesh yet on a fresh mount.
          setTimeout(applyTexture, 200);
          return;
        }
        const tex = new THREE.CanvasTexture(canvas);
        if ('colorSpace' in tex && THREE.SRGBColorSpace) {
          tex.colorSpace = THREE.SRGBColorSpace;
        }
        tex.minFilter = THREE.LinearFilter;   // NPOT canvas: no mipmaps
        tex.generateMipmaps = false;
        mesh.material = new THREE.MeshBasicMaterial({ map: tex });
        mesh.material.needsUpdate = true;
        textureRef.current = tex;
        // Hand the texture to the vnc-canvas-refresh component on this
        // entity, whose tick runs on the XR frame clock.
        plane.vncTexture = tex;
        setTextureCreated(true);
      };
      applyTexture();
    }

    if (onVNCReady) onVNCReady(idx, vncRef.current);
  };

  const handleVNCDisconnect = (instanceId, details) => {
    console.log(`VR: VNC disconnected for ${instanceId}`, details);
    setTextureCreated(false);
    
    if (planeRef.current) {
      planeRef.current.setAttribute('material', {
        color: '#222',
        src: null
      });
    }
  };

  const handleClick = () => {
    // Selection only. The old code also fired a fake left-click at (320,240) —
    // the centre of a screen size this guest does not even run — so merely
    // selecting a tile clicked something random in the game.
    setActive(idx);
    setActiveIds([inst.id]);
  };

  // The laser component emits UV-space pointer events on this tile's plane;
  // only here do UVs become framebuffer pixels, because only this tile knows
  // its canvas. UV origin is bottom-left, framebuffer origin is top-left.
  useEffect(() => {
    const plane = planeRef.current;
    if (!plane) return undefined;
    const onPointer = (e) => {
      const { u, v, mask, pressed } = e.detail;
      if (pressed) {
        setActive(idx);
        setActiveIds([inst.id]);
      }
      const ref = vncRef.current;
      if (!ref || !ref.getConnectionState().connected) return;
      const canvas = ref.getCanvas();
      const w = (canvas && canvas.width) || 1024;
      const h = (canvas && canvas.height) || 768;
      const x = Math.max(0, Math.min(w - 1, Math.round(u * (w - 1))));
      const y = Math.max(0, Math.min(h - 1, Math.round((1 - v) * (h - 1))));
      ref.sendMouse(x, y, mask);
    };
    plane.addEventListener('vnc-pointer', onPointer);
    return () => plane.removeEventListener('vnc-pointer', onPointer);
  }, [idx, inst.id, setActive, setActiveIds]);

  // reuse computed position
  // Compute audio ring scale from audioLevel (0-1) for 3D visualisation
  const ringScale = 1 + (liveAudioLevel || 0) * 0.6;
  const ringOpacity = Math.min(0.15 + (liveAudioLevel || 0) * 0.5, 0.7);
  const ringColor = muted ? '#666' : (active === idx ? '#FFD700' : '#3ABFF8');

  return (
    <>
      <VRNoVNCViewer
        ref={vncRef}
        instanceId={inst.id}
        onConnect={handleVNCConnect}
        onDisconnect={handleVNCDisconnect}
      />
      <video ref={rtcVideoRef} className="hidden" />
      
      <a-entity
        ref={(el) => {
          planeRef.current = el;
          // React does not reliably map className -> class on custom
          // elements, and the controllers' raycaster filters on ".tile";
          // if the class is missing the laser passes straight through.
          if (el) el.classList.add('tile');
        }}
        vnc-canvas-refresh=""
        position={`${pos.x} ${pos.y} ${active === idx ? 0.25 : 0}`}
        geometry="primitive: plane; width: 1.2; height: 0.9"
        material={`color: ${active === idx ? '#FFD700' : '#F5F5DC'}; side: double`}
        scale={active === idx ? '1.08 1.08 1' : '1 1 1'}
        onClick={handleClick}
      >
        {/* LEGO-style border for VR tiles */}
        <a-entity
          geometry="primitive: plane; width: 1.3; height: 1.0"
          material={`color: ${active === idx ? '#0055BF' : '#C4281C'}; side: double`}
          position="0 0 -0.01"
        />

        {/* Audio level ring — pulses with live audio level */}
        <a-entity
          geometry="primitive: ring; radiusInner: 0.55; radiusOuter: 0.62"
          material={`color: ${ringColor}; opacity: ${ringOpacity}; side: double; transparent: true`}
          scale={`${ringScale} ${ringScale} 1`}
          position="0 0 0.015"
        />

        {/* Mute indicator */}
        {muted && (
          <a-text
            value="🔇"
            align="center"
            width="0.6"
            position="0.5 -0.35 0.03"
          />
        )}
        
        {/* A live texture is ground truth; never contradict it with a
            status feed. /api/status once said "booting" forever over two
            perfectly running, VNC-connected guests. */}
        {status && status !== 'ready' && !textureCreated && (
          <a-text
            value={status}
            color={active === idx ? '#000000' : '#FFFFFF'}
            align="center"
            width="1.2"
            position="0 0 0.02"
            font="roboto"
          />
        )}
        
        {!textureCreated && (
          <a-text
            value={`${inst.name || inst.id}`}
            color={active === idx ? '#000000' : '#333333'}
            align="center"
            width="1.0"
            position="0 -0.3 0.02"
            font="roboto"
          />
        )}
        
        {!textureCreated && (
          <a-text
            value="Connecting..."
            color={active === idx ? '#666666' : '#CCCCCC'}
            align="center"
            width="0.8"
            position="0 0.3 0.02"
            font="roboto"
          />
        )}
      </a-entity>
    </>
  );
}

export default function VRScene({ onExit }) {
  const { activeIds, setActiveIds } = useActive();
  const [instances, setInstances] = useState([]);
  const [active, setActive] = useState(0);
  const [info, setInfo] = useState('');
  const [status, setStatus] = useState({});
  const [connectedVNCs, setConnectedVNCs] = useState(new Set());
  const [toast, setToast] = useState('');
  const [menuOpen, setMenuOpen] = useState(false);
  const [volumes, setVolumes] = useState([]);
  const [mutedTiles, setMutedTiles] = useState([]);
  const [audioLevels, setAudioLevels] = useState([]);
  const [monoAudio, setMonoAudio] = useState(false);
  const [audioResumed, setAudioResumed] = useState(false);
  const [sharedAudioCtx, setSharedAudioCtx] = useState(null);
  const [exportFormat, setExportFormat] = useState('webm');
  const ambientVolume = 0.2;

  // Lazily create a single shared AudioContext for all tiles
  const getSharedAudioCtx = useCallback(() => {
    if (!sharedAudioCtx) {
      const ctx = new (window.AudioContext || window.webkitAudioContext)();
      setSharedAudioCtx(ctx);
      return ctx;
    }
    return sharedAudioCtx;
  }, [sharedAudioCtx]);

  // Resume the shared context on first user gesture (autoplay policy)
  const handleAudioResume = useCallback(async () => {
    const ctx = getSharedAudioCtx();
    if (ctx.state === 'suspended') {
      await ctx.resume();
    }
    setAudioResumed(true);
  }, [getSharedAudioCtx]);

  // Sync the AudioContext listener with the VR camera rig position
  useVRAudioListener(sharedAudioCtx);

  // Where the screen wall sits and how big it is. The reviewer's complaint
  // was concrete: too far, no way to move or resize, and overlap once
  // scaled. Distance and scale are user-adjustable and remembered; overlap
  // is prevented structurally (the active tile pops FORWARD instead of
  // growing over its neighbours).
  const [wallZ, setWallZ] = useState(() => {
    const v = parseFloat(localStorage.getItem('vrWallZ'));
    return Number.isFinite(v) ? Math.min(-1.2, Math.max(-4.5, v)) : -2.4;
  });
  const [wallScale, setWallScale] = useState(() => {
    const v = parseFloat(localStorage.getItem('vrWallScale'));
    return Number.isFinite(v) ? Math.min(2.2, Math.max(0.5, v)) : 1;
  });
  useEffect(() => { localStorage.setItem('vrWallZ', String(wallZ)); }, [wallZ]);
  useEffect(() => { localStorage.setItem('vrWallScale', String(wallScale)); }, [wallScale]);

  useEffect(() => {
    const left = document.getElementById('leftController');
    if (!left) return undefined;
    const onStick = (e) => {
      const { x, y } = e.detail || {};
      if (typeof y === 'number' && Math.abs(y) > 0.25) {
        // Push forward (stick up, negative y) to push the wall away.
        setWallZ((z) => Math.min(-1.2, Math.max(-4.5, z + (y > 0 ? 0.04 : -0.04) * Math.abs(y))));
      }
      if (typeof x === 'number' && Math.abs(x) > 0.25) {
        setWallScale((s) => Math.min(2.2, Math.max(0.5, s * (1 + 0.02 * x))));
      }
    };
    left.addEventListener('thumbstickmoved', onStick);
    return () => left.removeEventListener('thumbstickmoved', onStick);
  }, []);

  // Unlock audio from INSIDE immersive mode. The DOM "Enable Audio" button
  // does not exist once the headset takes over, so a session that never
  // clicked it beforehand stayed silent with no way to fix it. enter-vr is a
  // user gesture, and so is every controller button.
  useEffect(() => {
    const scene = document.querySelector('a-scene');
    if (!scene) return undefined;
    const unlock = () => { handleAudioResume(); };
    scene.addEventListener('enter-vr', unlock);
    const controllers = ['leftController', 'rightController']
      .map((id) => document.getElementById(id))
      .filter(Boolean);
    controllers.forEach((c) => {
      c.addEventListener('triggerdown', unlock);
      c.addEventListener('gripdown', unlock);
    });
    return () => {
      scene.removeEventListener('enter-vr', unlock);
      controllers.forEach((c) => {
        c.removeEventListener('triggerdown', unlock);
        c.removeEventListener('gripdown', unlock);
      });
    };
  }, [handleAudioResume]);

  // Feed the camera-locked HUD. Plain attribute writes — the entity lives
  // outside React's render on purpose, so headset pose changes never
  // re-render the tree.
  useEffect(() => {
    const hud = document.getElementById('vrHud');
    if (!hud) return;
    const activeInst = instances[active];
    hud.setAttribute('text', 'value',
      `tile ${active + 1}/${instances.length} ${activeInst ? activeInst.id : ''}` +
      ` | vnc ${connectedVNCs.size}/${instances.length}` +
      ` | audio ${audioResumed ? 'on' : 'press trigger'}` +
      ` | wall ${Math.abs(wallZ).toFixed(1)}m x${wallScale.toFixed(2)} (L-stick)`);
  }, [active, instances, connectedVNCs, audioResumed, wallZ, wallScale]);

  // Performance recorder for spatial audio metrics
  const {
    recording: perfRecording,
    startRecording: startPerfRecording,
    recordTileSnapshot,
    exportRecording: exportPerfRecording,
  } = usePerformanceRecorder();

  // Video recorder for canvas capture (multi-format)
  const {
    videoRecording,
    startVideoRecording,
    stopVideoRecording,
  } = useVideoRecorder(exportFormat);

  // Declared BEFORE any hook that lists them in a dependency array. A deps
  // array is evaluated during render, so when these consts lived at the
  // bottom of the component the read hit the temporal dead zone and threw on
  // the very first render — with no error boundary above, React 18 unmounted
  // the entire root: the "blank white screen" on every headset and desktop.
  const cols = Math.ceil(Math.sqrt(instances.length || 1));
  const rows = Math.ceil((instances.length || 1) / cols);

  // Feed tile snapshot into the recorder each time volumes/active change
  useEffect(() => {
    if (!perfRecording) return;
    const tileData = instances.map((inst, idx) => {
      const p = positionForIndex(idx, cols, rows);
      return { id: inst.id, volume: volumes[idx] || 1, position: { x: p.x, y: p.y, z: -3 } };
    });
    recordTileSnapshot(active, monoAudio, tileData);
  }, [perfRecording, active, monoAudio, volumes, instances, cols, rows, recordTileSnapshot]);

  const handleTogglePerfRecording = useCallback(() => {
    if (perfRecording) {
      exportPerfRecording();
      setToast('Performance log exported');
    } else if (sharedAudioCtx) {
      startPerfRecording(sharedAudioCtx);
      setToast('Recording started');
    }
  }, [perfRecording, sharedAudioCtx, exportPerfRecording, startPerfRecording]);

  const handleToggleVideoRecording = useCallback(() => {
    if (videoRecording) {
      stopVideoRecording();
      setToast(`${EXPORT_FORMATS[exportFormat]?.label || 'File'} saved`);
    } else {
      startVideoRecording();
      setToast(`Recording ${EXPORT_FORMATS[exportFormat]?.label || exportFormat}…`);
    }
  }, [videoRecording, startVideoRecording, stopVideoRecording, exportFormat]);

  // Clean up shared context on unmount
  useEffect(() => {
    return () => {
      if (sharedAudioCtx) {
        sharedAudioCtx.close();
      }
    };
  }, [sharedAudioCtx]);
  // Trigger, grip, B and pinch belong to the pointer (vnc-laser-input above):
  // trigger = left click, grip/B = right click. They must not double as keys —
  // the old trigger->Enter mapping meant every click also typed Enter.
  const defaultControllerMap = {
    abuttondown: 'F1',
    xbuttondown: 'F3',
    ybuttondown: 'F4',
    abuttonup: 'F1',
    xbuttonup: 'F3',
    ybuttonup: 'F4',
  };
  const sanitizeControllerMap = (m) => {
    const out = { ...m };
    VNC_LASER_RESERVED.forEach((ev) => delete out[ev]);
    return out;
  };
  const defaultKeyboardMap = {
    Enter: 0xFF0D,
    Backspace: 0xFF08,
    Tab: 0xFF09,
    Escape: 0xFF1B,
    ArrowUp: 0xFF52,
    ArrowDown: 0xFF54,
    ArrowLeft: 0xFF51,
    ArrowRight: 0xFF53,
    F1: 0xFFBE,
    F2: 0xFFBF,
    F3: 0xFFC0,
    F4: 0xFFC1,
    F5: 0xFFC2,
    F6: 0xFFC3,
    F7: 0xFFC4,
    F8: 0xFFC5,
    F9: 0xFFC6,
    F10: 0xFFC7,
    F11: 0xFFC8,
    F12: 0xFFC9,
  };
  const [controllerMap, setControllerMapRaw] = useState(() => {
    try {
      return sanitizeControllerMap({
        ...defaultControllerMap,
        ...JSON.parse(localStorage.getItem('vrControllerMap') || '{}'),
      });
    } catch {
      return defaultControllerMap;
    }
  });
  const setControllerMap = useCallback(
    (next) => setControllerMapRaw(
      typeof next === 'function'
        ? (prev) => sanitizeControllerMap(next(prev))
        : sanitizeControllerMap(next)),
    []);
  const [keyboardMap, setKeyboardMap] = useState(() => {
    try {
      return {
        ...defaultKeyboardMap,
        ...JSON.parse(localStorage.getItem('vrKeyboardMap') || '{}'),
      };
    } catch {
      return defaultKeyboardMap;
    }
  });
  const vncRefs = useRef([]);

  const showToast = (msg) => {
    setToast(msg);
    setTimeout(() => setToast(''), 3000);
  };

  const saveMappings = (cMap, kMap) => {
    const mergedController = sanitizeControllerMap({ ...defaultControllerMap, ...cMap });
    const mergedKeyboard = { ...defaultKeyboardMap, ...kMap };
    setControllerMap(mergedController);
    setKeyboardMap(mergedKeyboard);
    localStorage.setItem('vrControllerMap', JSON.stringify(mergedController));
    localStorage.setItem('vrKeyboardMap', JSON.stringify(mergedKeyboard));
  };

  useEffect(() => {
    // /api/instances, NOT /api/config/instances: the latter is a static
    // config file that lists two instances forever, while the grid uses live
    // Kubernetes discovery. Scaling the cluster to four left the VR view
    // stuck at two — same fossil-config failure mode as /api/status.
    fetch('/api/instances')
      .then((r) => r.json())
      .then((data) => {
        if (Array.isArray(data) && data.length) {
          setInstances(data);
          vncRefs.current = new Array(data.length);
          setVolumes(new Array(data.length).fill(1));
          setMutedTiles(new Array(data.length).fill(false));
          setAudioLevels(new Array(data.length).fill(0));
        } else {
          throw new Error('no data');
        }
      })
      .catch(() => {
        setInstances(
          Array.from({ length: 3 }, (_, i) => ({ id: `placeholder-${i}` }))
        );
        vncRefs.current = new Array(3);
        setVolumes(new Array(3).fill(1));
        setMutedTiles(new Array(3).fill(false));
        setAudioLevels(new Array(3).fill(0));
        setInfo('Using placeholder streams');
      });
    
    const interval = setInterval(() => {
      fetch('/api/status')
        .then((r) => r.json())
        .then(setStatus)
        .catch(() => {});
    }, 5000);
    
    fetch('/api/status').then((r) => r.json()).then(setStatus).catch(() => {});
    return () => clearInterval(interval);
  }, []);

  // Update active index when activeIds change
  useEffect(() => {
    if (!activeIds.length || instances.length === 0) return;
    const idx = instances.findIndex((i) => i.id === activeIds[0]);
    if (idx >= 0) setActive(idx);
  }, [activeIds, instances]);

  useEffect(() => {
    const handler = (e) => {
      if (e.key === 'm' && e.type === 'keydown') {
        setMenuOpen((m) => !m);
        return;
      }
      if (e.key >= '1' && e.key <= '9') {
        const idx = parseInt(e.key) - 1;
        if (idx < instances.length) {
          setActive(idx);
          setActiveIds([instances[idx].id]);
        }
      } else if (connectedVNCs.has(active) && vncRefs.current[active]) {
        const vncRef = vncRefs.current[active];
        if (vncRef && vncRef.getConnectionState().connected) {
          let keysym = 0;
          
          if (e.key.length === 1) {
            keysym = e.key.charCodeAt(0);
          } else {
            keysym = keyboardMap[e.key] || 0;
          }
          
          if (keysym) {
            vncRef.sendKey(keysym, e.type === 'keydown' ? 1 : 0);
          }
        }
      }
      
      console.log('VR KVM event to tile', active + 1, e.key);
    };
    
    window.addEventListener('keydown', handler);
    window.addEventListener('keyup', handler);
    return () => {
      window.removeEventListener('keydown', handler);
      window.removeEventListener('keyup', handler);
    };
  }, [active, instances.length, connectedVNCs, keyboardMap]);

  useEffect(() => {
    const left = document.getElementById('leftController');
    const right = document.getElementById('rightController');
    if (!left || !right) return;

    const specialKeys = keyboardMap;
    const map = controllerMap;

    const handler = (e) => {
      if (e.type === 'ybuttondown') {
        setMenuOpen(m => !m);
        return;
      }
      const keyName = map[e.type];
      if (!keyName) return;
      const vncRef = vncRefs.current[active];
      if (!connectedVNCs.has(active) || !vncRef) return;
      if (!vncRef.getConnectionState().connected) return;
      const keysym = specialKeys[keyName];
      vncRef.sendKey(keysym, e.type.endsWith('down') ? 1 : 0);
    };

    const events = Object.keys(map);
    events.forEach(ev => {
      left.addEventListener(ev, handler);
      right.addEventListener(ev, handler);
    });

    return () => {
      events.forEach(ev => {
        left.removeEventListener(ev, handler);
        right.removeEventListener(ev, handler);
      });
    };
  }, [active, connectedVNCs, controllerMap, keyboardMap]);

  const handleVNCReady = (idx, vncRef) => {
    vncRefs.current[idx] = vncRef;
    setConnectedVNCs(prev => new Set([...prev, idx]));
  };

  const handleAudioLevel = useCallback((idx, level) => {
    setAudioLevels(prev => {
      if (prev[idx] === level) return prev;
      const arr = [...prev];
      arr[idx] = level;
      return arr;
    });
  }, []);

  return (
    <div className="w-full h-full relative">
      <div className="absolute top-4 left-4 text-black z-10 font-sans text-sm bg-white/90 p-3 rounded-lg border-2 border-red-600">
        <div className="font-bold text-red-600 mb-2">🎮 LEGO LOCO VR</div>
        <div>Active tile: <span className="font-bold text-blue-600">{active + 1}</span> <span className="text-gray-600">{info}</span></div>
        <div className="text-xs text-gray-700 mt-1">
          VNC Connected: <span className="font-bold text-green-600">{connectedVNCs.size}</span>/{instances.length}
        </div>
        <div className="text-xs text-gray-700">
          Keys 1-9: Switch tiles | Type to control active emulator
        </div>
      </div>
      
      <div className="absolute top-4 right-4 z-10">
        <button
          onClick={onExit}
          className="lego-vr-button bg-yellow-400 text-black px-4 py-2 rounded-lg border-3 border-red-600 font-bold shadow-lg hover:bg-yellow-300"
        >
          🚪 Exit VR
        </button>
        <div className="inline-block ml-2">
          <ControlsConfig
            controllerMap={controllerMap}
            keyboardMap={keyboardMap}
            onSave={saveMappings}
            showToast={showToast}
          />
        </div>
      </div>

      <div className="absolute bottom-4 left-4 z-10 bg-white/90 p-2 rounded-lg border-2 border-yellow-400" role="group" aria-label="Audio controls">
        <label className="text-sm font-bold text-black mb-1 block">🔊 Volume:</label>
        <input
          type="range"
          min="0"
          max="1"
          step="0.01"
          aria-label={`Volume for tile ${active + 1}`}
          value={volumes[active] || 1}
          onChange={(e) => {
            const v = parseFloat(e.target.value);
            setVolumes((vals) => {
              const arr = [...vals];
              arr[active] = v;
              return arr;
            });
          }}
          className="w-20"
        />
        <span className="text-xs font-bold text-black ml-1">{Math.round((volumes[active] || 1) * 100)}%</span>
        {/* Audio level meter for active tile */}
        <div className="flex items-center gap-1 mt-1">
          <span className="text-xs text-gray-600">🎵</span>
          <div className="flex-1 h-1.5 bg-gray-300 rounded-full overflow-hidden w-20">
            <div
              className="h-full rounded-full transition-all duration-75"
              style={{
                width: `${Math.min((audioLevels[active] || 0) * 100, 100)}%`,
                backgroundColor: (audioLevels[active] || 0) > 0.75 ? '#ef4444' : (audioLevels[active] || 0) > 0.4 ? '#eab308' : '#22c55e'
              }}
            />
          </div>
        </div>
        <div className="flex items-center mt-1 gap-2">
          <button
            onClick={() => {
              setMutedTiles((m) => {
                const arr = [...m];
                arr[active] = !arr[active];
                return arr;
              });
            }}
            className={`text-xs px-2 py-0.5 rounded border font-bold ${mutedTiles[active] ? 'bg-gray-400 text-white border-gray-600' : 'bg-green-500 text-white border-green-700'}`}
            aria-pressed={!mutedTiles[active]}
            title={mutedTiles[active] ? 'Unmute this tile' : 'Mute this tile'}
          >
            {mutedTiles[active] ? '🔇 Muted' : '🔊 On'}
          </button>
          <button
            onClick={() => setMonoAudio((m) => !m)}
            className={`text-xs px-2 py-0.5 rounded border font-bold ${monoAudio ? 'bg-blue-500 text-white border-blue-700' : 'bg-gray-200 text-black border-gray-400'}`}
            aria-pressed={monoAudio}
            title="Mono audio disables 3D spatial sound for accessibility"
          >
            {monoAudio ? '🔈 Mono' : '🎧 3D'}
          </button>
          <button
            onClick={handleTogglePerfRecording}
            className={`text-xs px-2 py-0.5 rounded border font-bold ${perfRecording ? 'bg-red-500 text-white border-red-700 animate-pulse' : 'bg-gray-200 text-black border-gray-400'}`}
            aria-pressed={perfRecording}
            title={perfRecording ? 'Stop recording and export performance log' : 'Start recording spatial audio performance'}
          >
            {perfRecording ? '⏹ Export Log' : '⏺ Record Perf'}
          </button>
          <select
            value={exportFormat}
            onChange={(e) => setExportFormat(e.target.value)}
            disabled={videoRecording}
            className="text-xs px-1 py-0.5 rounded border font-bold bg-gray-200 text-black border-gray-400"
            aria-label="Export format"
            title="Choose recording format"
          >
            {FORMAT_KEYS.map((k) => (
              <option key={k} value={k}>
                {EXPORT_FORMATS[k].label}
              </option>
            ))}
          </select>
          <button
            onClick={handleToggleVideoRecording}
            className={`text-xs px-2 py-0.5 rounded border font-bold ${videoRecording ? 'bg-red-500 text-white border-red-700 animate-pulse' : 'bg-gray-200 text-black border-gray-400'}`}
            aria-pressed={videoRecording}
            title={videoRecording ? `Stop recording and save ${EXPORT_FORMATS[exportFormat]?.label}` : `Record VR scene as ${EXPORT_FORMATS[exportFormat]?.label}`}
          >
            {videoRecording ? `⏹ Save ${EXPORT_FORMATS[exportFormat]?.label}` : `🎥 Rec ${EXPORT_FORMATS[exportFormat]?.label}`}
          </button>
          {!audioResumed && (
            <button
              onClick={handleAudioResume}
              className="text-xs px-2 py-0.5 rounded border font-bold bg-green-400 text-black border-green-600 animate-pulse"
              aria-label="Enable audio playback"
            >
              ▶ Enable Audio
            </button>
          )}
        </div>
      </div>

      {menuOpen && (
        <div className="absolute bottom-16 left-1/2 transform -translate-x-1/2 bg-cream border-4 border-red-600 rounded-lg shadow-lg z-10 p-3">
          <div className="text-sm font-bold text-black mb-2 text-center">🎯 Select Instance</div>
          {instances.map((inst, idx) => (
            <button
              key={inst.id}
              onClick={() => {
                setActive(idx);
                setActiveIds([inst.id]);
                setMenuOpen(false);
              }}
              className="block text-sm text-black px-3 py-2 w-full text-left hover:bg-yellow-200 rounded border-2 border-transparent hover:border-blue-400 font-bold mb-1"
            >
              🎮 {inst.name || inst.id}
            </button>
          ))}
        </div>
      )}
      
      <a-scene embedded>
        <a-assets>
        </a-assets>
        
        {/* The tile wall. One parent owns where the screens ARE — at eye
            height, adjustable with the LEFT thumbstick (fwd/back = closer or
            farther, left/right = smaller or larger), persisted per browser.
            Scaling happens about eye height, so growing the wall does not
            lift it away from the horizon. movement-controls on the rig was a
            reference to a library this app has never shipped, which is why
            nothing could ever be moved. */}
        <a-entity
          id="tileWall"
          position={`0 1.5 ${wallZ}`}
          scale={`${wallScale} ${wallScale} 1`}
        >
          {instances.map((inst, idx) => (
            <VRTile
              key={inst.id}
              wallZ={wallZ}
              inst={inst}
              idx={idx}
              active={active}
              setActive={setActive}
              setActiveIds={setActiveIds}
              activeIds={activeIds}
              cols={cols}
              rows={rows}
              status={status[inst.id]}
              volume={volumes[idx] || 1}
              ambientVolume={ambientVolume}
              onVNCReady={handleVNCReady}
              sharedAudioCtx={sharedAudioCtx}
              monoAudio={monoAudio}
              muted={mutedTiles[idx] || false}
              audioLevel={audioLevels[idx] || 0}
              onAudioLevel={handleAudioLevel}
            />
          ))}
        </a-entity>
        
        {/* Sky-blue sky; the green went to the baseplate below, where LEGO
            green belongs. An all-green sphere with no horizon reads as a
            void with no way to orient. */}
        <a-sky color="#5C9DD6"></a-sky>
        
        {/* LEGO baseplate grid pattern in 3D space */}
        <a-entity
          geometry="primitive: plane; width: 20; height: 20"
          material="color: #00A651; opacity: 1"
          position="0 0 -5"
          rotation="-90 0 0"
        >
          {/* Grid lines for LEGO baseplate effect */}
          {Array(20).fill(0).map((_, i) => (
            <a-entity key={`grid-${i}`}>
              <a-entity
                geometry={`primitive: plane; width: 20; height: 0.02`}
                material="color: #ffffff; opacity: 0.1"
                position={`0 0 ${(i - 10) * 1}`}
              />
              <a-entity
                geometry={`primitive: plane; width: 0.02; height: 20`}
                material="color: #ffffff; opacity: 0.1"
                position={`${(i - 10) * 1} 0 0`}
              />
            </a-entity>
          ))}
        </a-entity>
        
        {/* Rig at floor level: with local-floor XR the headset adds the
            user's physical height, so a 1.6 here doubled it — the reviewer
            floated ~3.3m up. The camera keeps 1.6 for DESKTOP only; in VR
            A-Frame replaces the camera pose with the headset's. */}
        <a-entity
          id="rig"
          movement-controls
          position="0 0 0.6"
        >
          <a-entity
            camera
            position="0 1.6 0"
            look-controls
            wasd-controls
            cursor="rayOrigin: mouse"
          >
            {/* In-headset HUD: the DOM overlays do not exist in immersive
                mode, which read as "no stats". Locked to the camera. */}
            <a-entity
              position="0 -0.42 -0.9"
              text="value: ; align: center; color: #9be7a1; width: 1.6"
              id="vrHud"
            ></a-entity>
          </a-entity>
          
          <a-entity
            id="leftController"
            oculus-touch-controls="hand: left"
            hand-tracking-controls="hand: left"
          ></a-entity>
          
          <a-entity
            id="rightController"
            oculus-touch-controls="hand: right"
            hand-tracking-controls="hand: right"
            laser-controls
            raycaster="objects: .tile"
            cursor="fuse: false"
            vnc-laser-input=""
          ></a-entity>
          <VRToast message={toast} />
        </a-entity>
      </a-scene>
    </div>
  );
}
