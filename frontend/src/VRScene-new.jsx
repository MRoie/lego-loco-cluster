import 'aframe';
import React, { useEffect, useState, useRef } from 'react';
import VRNoVNCViewer from './components/VRNoVNCViewer';
import { createLogger } from './utils/logger.js';

function positionForIndex(i, cols, rows) {
  const x = (i % cols) - (cols - 1) / 2;
  const row = Math.floor(i / cols);
  const y = (rows - 1) / 2 - row;
  return { x: x * 1.4, y: y * 1.0 };
}

function VRTile({ inst, idx, active, setActive, cols, rows, status, onVNCReady }) {
  const logger = createLogger(`VRTile-${idx}`);
  const vncRef = useRef(null);
  const planeRef = useRef(null);
  const [textureCreated, setTextureCreated] = useState(false);

  const handleVNCConnect = (instanceId) => {
    logger.info('VNC connected for VR tile', { instanceId });
    
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
    logger.info('VNC disconnected for VR tile', { instanceId, details });
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

  const pos = positionForIndex(idx, cols, rows);

  return (
    <>
      <VRNoVNCViewer
        ref={vncRef}
        instanceId={inst.id}
        onConnect={handleVNCConnect}
        onDisconnect={handleVNCDisconnect}
      />
      
      <a-entity
        class="tile"
        position={`${pos.x} ${pos.y} -3`}
        geometry="primitive: plane; width: 1.2; height: 0.9"
        material={`color: ${active === idx ? '#555' : '#222'}`}
        scale={active === idx ? '1.4 1.4 1' : '1 1 1'}
        ref={planeRef}
        onClick={handleClick}
      >
        {status && status !== 'ready' && (
          <a-text
            value={status}
            color="#FFF"
            align="center"
            width="1.2"
            position="0 0 0.02"
          />
        )}
        
        {!textureCreated && (
          <a-text
            value={`Connecting to ${inst.id}...`}
            color="#FFF"
            align="center"
            width="1.0"
            position="0 0 0.02"
            font="roboto"
          />
        )}
      </a-entity>
    </>
  );
}

export default function VRScene({ onExit }) {
  const logger = createLogger('VRScene');
  const [instances, setInstances] = useState([]);
  const [active, setActive] = useState(0);
  const [info, setInfo] = useState('');
  const [status, setStatus] = useState({});
  const [connectedVNCs, setConnectedVNCs] = useState(new Set());
  const vncRefs = useRef([]);

  useEffect(() => {
    fetch('/api/config/instances')
      .then((r) => r.json())
      .then((data) => {
        if (Array.isArray(data) && data.length) {
          setInstances(data);
          vncRefs.current = new Array(data.length);
        } else {
          throw new Error('no data');
        }
      })
      .catch(() => {
        setInstances(
          Array.from({ length: 3 }, (_, i) => ({ id: `placeholder-${i}` }))
        );
        vncRefs.current = new Array(3);
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

  useEffect(() => {
    const handler = (e) => {
      if (e.key >= '1' && e.key <= '9') {
        const idx = parseInt(e.key) - 1;
        if (idx < instances.length) {
          setActive(idx);
        }
      } else if (connectedVNCs.has(active) && vncRefs.current[active]) {
        const vncRef = vncRefs.current[active];
        if (vncRef && vncRef.getConnectionState().connected) {
          let keysym = 0;
          
          if (e.key.length === 1) {
            keysym = e.key.charCodeAt(0);
          } else {
            const specialKeys = {
              'Enter': 0xFF0D,
              'Backspace': 0xFF08,
              'Tab': 0xFF09,
              'Escape': 0xFF1B,
              'ArrowUp': 0xFF52,
              'ArrowDown': 0xFF54,
              'ArrowLeft': 0xFF51,
              'ArrowRight': 0xFF53,
              'F1': 0xFFBE,
              'F2': 0xFFBF,
              'F3': 0xFFC0,
              'F4': 0xFFC1,
              'F5': 0xFFC2,
              'F6': 0xFFC3,
              'F7': 0xFFC4,
              'F8': 0xFFC5,
              'F9': 0xFFC6,
              'F10': 0xFFC7,
              'F11': 0xFFC8,
              'F12': 0xFFC9
            };
            keysym = specialKeys[e.key] || 0;
          }
          
          if (keysym) {
            vncRef.sendKey(keysym, e.type === 'keydown' ? 1 : 0);
          }
        }
      }
      
      logger.debug('VR KVM event to tile', { tileNumber: active + 1, key: e.key });
    };
    
    window.addEventListener('keydown', handler);
    window.addEventListener('keyup', handler);
    return () => {
      window.removeEventListener('keydown', handler);
      window.removeEventListener('keyup', handler);
    };
  }, [active, instances.length, connectedVNCs]);

  const handleVNCReady = (idx, vncRef) => {
    vncRefs.current[idx] = vncRef;
    setConnectedVNCs(prev => new Set([...prev, idx]));
  };

  const cols = Math.ceil(Math.sqrt(instances.length || 1));
  const rows = Math.ceil((instances.length || 1) / cols);

  return (
    <div className="w-full h-full relative">
      <div className="absolute top-4 left-4 text-white z-10 font-sans text-sm">
        Active tile: {active + 1} <span className="text-gray-400">{info}</span>
        <div className="text-xs text-gray-300 mt-1">
          VNC Connected: {connectedVNCs.size}/{instances.length}
        </div>
        <div className="text-xs text-gray-300">
          Keys 1-9: Switch tiles | Type to control active emulator
        </div>
      </div>
      
      <div className="absolute top-4 right-4 z-10">
        <button
          onClick={onExit}
          className="bg-yellow-500 text-black px-3 py-1 rounded"
        >
          Exit VR
        </button>
      </div>
      
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
              cols={cols}
              rows={rows}
              status={status[inst.id]}
              onVNCReady={handleVNCReady}
            />
          ))}
        </a-entity>
        
        <a-sky color="#111"></a-sky>
        
        <a-entity 
          id="rig" 
          movement-controls 
          position="0 1.6 3"
        >
          <a-entity 
            camera 
            look-controls 
            wasd-controls
          ></a-entity>
          
          <a-entity 
            id="leftController"
            oculus-touch-controls="hand: left"
          ></a-entity>
          
          <a-entity 
            id="rightController" 
            oculus-touch-controls="hand: right"
            laser-controls
            raycaster="objects: .tile"
          ></a-entity>
        </a-entity>
      </a-scene>
    </div>
  );
}
