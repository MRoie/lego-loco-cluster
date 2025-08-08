import 'aframe';
import React, { useEffect, useState, useRef } from 'react';
import { useActive } from './ActiveContext';
import useWebRTC from './hooks/useWebRTC';
import useSpatialAudio from './hooks/useSpatialAudio';
import VRReactVNCViewer from './components/VRReactVNCViewer';
import ControlsConfig from './components/ControlsConfig';
import VRToast from './components/VRToast';

function positionForIndex(i, cols, rows) {
  const x = (i % cols) - (cols - 1) / 2;
  const row = Math.floor(i / cols);
  const y = (rows - 1) / 2 - row;
  return { x: x * 1.4, y: y * 1.0 };
}

function VRTile({ inst, idx, active, setActive, setActiveIds, cols, rows, status, onVNCReady, volume, ambientVolume, activeIds }) {
  const vncRef = useRef(null);
  const planeRef = useRef(null);
  const [textureCreated, setTextureCreated] = useState(false);
  const { videoRef: rtcVideoRef } = useWebRTC(inst.id);
  const pos = positionForIndex(idx, cols, rows);
  const { setVolume } = useSpatialAudio(rtcVideoRef, [pos.x, pos.y, -3]);


  useEffect(() => {
    const finalVol = volume * (activeIds.includes(inst.id) ? 1 : ambientVolume);
    setVolume(finalVol);
  }, [volume, activeIds, inst.id, ambientVolume, setVolume]);

  const handleVNCConnect = (instanceId) => {
    console.log(`VR: VNC connected for ${instanceId}`);
    
    // Get the canvas from the VNC viewer
    const canvas = vncRef.current?.getCanvas();
    if (canvas && planeRef.current) {
      // Create a canvas texture for A-Frame
      const scene = document.querySelector('a-scene');
      if (scene) {
        // Register the canvas as a texture asset
        const textureId = `vnc-texture-${idx}`;
        
        // Remove existing texture if any
        const existingAsset = scene.querySelector(`#${textureId}`);
        if (existingAsset) {
          existingAsset.remove();
        }

        // Create new canvas asset
        const canvasAsset = document.createElement('a-asset-item');
        canvasAsset.setAttribute('id', textureId);
        canvasAsset.setAttribute('src', canvas);
        
        // Add to assets
        let assets = scene.querySelector('a-assets');
        if (!assets) {
          assets = document.createElement('a-assets');
          scene.appendChild(assets);
        }
        assets.appendChild(canvasAsset);

        // Apply texture to plane
        const plane = planeRef.current;
        plane.setAttribute('material', {
          src: `#${textureId}`,
          transparent: false,
          shader: 'flat'
        });

        setTextureCreated(true);
        
        // Set up continuous texture updates
        const updateTexture = () => {
          if (canvas && plane.getAttribute('material')) {
            const material = plane.components.material.material;
            if (material && material.map) {
              material.map.needsUpdate = true;
            }
          }
          requestAnimationFrame(updateTexture);
        };
        updateTexture();
      }
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
    setActive(idx);
    setActiveIds([inst.id]);
    
    if (vncRef.current) {
      const connectionState = vncRef.current.getConnectionState();
      if (connectionState.connected) {
        vncRef.current.sendMouse(320, 240, 1);
        setTimeout(() => {
          vncRef.current.sendMouse(320, 240, 0);
        }, 100);
      }
    }
  };

  // reuse computed position
  return (
    <>
      <VRReactVNCViewer
        ref={vncRef}
        instanceId={inst.id}
        onConnect={handleVNCConnect}
        onDisconnect={handleVNCDisconnect}
      />
      <video ref={rtcVideoRef} className="hidden" />
      
      <a-entity
        className="tile"
        position={`${pos.x} ${pos.y} -3`}
        geometry="primitive: plane; width: 1.2; height: 0.9"
        material={`color: ${active === idx ? '#FFD700' : '#F5F5DC'}; side: double`}
        scale={active === idx ? '1.4 1.4 1' : '1 1 1'}
        ref={planeRef}
        onClick={handleClick}
      >
        {/* LEGO-style border for VR tiles */}
        <a-entity
          geometry="primitive: plane; width: 1.3; height: 1.0"
          material={`color: ${active === idx ? '#0055BF' : '#C4281C'}; side: double`}
          position="0 0 -0.01"
        />
        
        {status && status !== 'ready' && (
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
  const ambientVolume = 0.2;
  const defaultControllerMap = {
    abuttondown: 'F1',
    bbuttondown: 'F2',
    xbuttondown: 'F3',
    ybuttondown: 'F4',
    triggerdown: 'Enter',
    abuttonup: 'F1',
    bbuttonup: 'F2',
    xbuttonup: 'F3',
    ybuttonup: 'F4',
    triggerup: 'Enter',
    pinchstarted: 'Enter',
    pinchended: 'Enter',
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
  const [controllerMap, setControllerMap] = useState(() => {
    try {
      return {
        ...defaultControllerMap,
        ...JSON.parse(localStorage.getItem('vrControllerMap') || '{}'),
      };
    } catch {
      return defaultControllerMap;
    }
  });
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
    const mergedController = { ...defaultControllerMap, ...cMap };
    const mergedKeyboard = { ...defaultKeyboardMap, ...kMap };
    setControllerMap(mergedController);
    setKeyboardMap(mergedKeyboard);
    localStorage.setItem('vrControllerMap', JSON.stringify(mergedController));
    localStorage.setItem('vrKeyboardMap', JSON.stringify(mergedKeyboard));
  };

  useEffect(() => {
    fetch('/api/config/instances')
      .then((r) => r.json())
      .then((data) => {
        if (Array.isArray(data) && data.length) {
          setInstances(data);
          vncRefs.current = new Array(data.length);
          setVolumes(new Array(data.length).fill(1));
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

  const cols = Math.ceil(Math.sqrt(instances.length || 1));
  const rows = Math.ceil((instances.length || 1) / cols);

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

      <div className="absolute bottom-4 left-4 z-10 bg-white/90 p-2 rounded-lg border-2 border-yellow-400">
        <label className="text-sm font-bold text-black mb-1 block">🔊 Volume:</label>
        <input
          type="range"
          min="0"
          max="1"
          step="0.01"
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
        
        <a-entity>
          {instances.map((inst, idx) => (
            <VRTile
              key={inst.id}
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
            />
          ))}
        </a-entity>
        
        <a-sky color="#00A651"></a-sky>
        
        {/* LEGO baseplate grid pattern in 3D space */}
        <a-entity
          geometry="primitive: plane; width: 20; height: 20"
          material="color: #00A651; opacity: 0.8"
          position="0 -2 -5"
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
        
        <a-entity 
          id="rig" 
          movement-controls 
          position="0 1.6 3"
        >
          <a-entity
            camera
            look-controls
            wasd-controls
            cursor="rayOrigin: mouse"
          ></a-entity>
          
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
          ></a-entity>
          <VRToast message={toast} />
        </a-entity>
      </a-scene>
    </div>
  );
}
