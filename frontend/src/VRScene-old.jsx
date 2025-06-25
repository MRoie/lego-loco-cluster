import 'aframe';
import React, { useEffect, useState, useRef } from 'react';
import VRNoVNCViewer from './components/VRNoVNCViewer';

function positionForIndex(i, cols, rows) {
  const x = (i % cols) - (cols - 1) / 2;
  const row = Math.floor(i / cols);
  const y = (rows - 1) / 2 - row;
  return { x: x * 1.4, y: y * 1.0 };
}

function VRTile({ inst, idx, active, setActive, cols, rows, status, onVNCReady }) {
  const vncRef = useRef(null);
  const planeRef = useRef(null);
  const [textureCreated, setTextureCreated] = useState(false);

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
          shader: 'flat' // Use flat shader for better performance
        });

        setTextureCreated(true);
        
        // Set up continuous texture updates
        const updateTexture = () => {
          if (canvas && plane.getAttribute('material')) {
            // Force texture update
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
    
    // Reset material to default
    if (planeRef.current) {
      planeRef.current.setAttribute('material', {
        color: '#222',
        src: null
      });
    }
  };

  const handleClick = () => {
    setActive(idx);
    
    // Send click to VNC if connected
    if (vncRef.current) {
      const connectionState = vncRef.current.getConnectionState();
      if (connectionState.connected) {
        // Send mouse click at center of screen
        vncRef.current.sendMouse(320, 240, 1); // Left click down
        setTimeout(() => {
          vncRef.current.sendMouse(320, 240, 0); // Release
        }, 100);
      }
    }
  };

  const pos = positionForIndex(idx, cols, rows);

  return (
    <>
      {/* Hidden VNC viewer that provides the canvas texture */}
      <VRNoVNCViewer
        ref={vncRef}
        instanceId={inst.id}
        onConnect={handleVNCConnect}
        onDisconnect={handleVNCDisconnect}
      />
      
      {/* VR plane that displays the VNC canvas */}
      <a-entity
        class="tile"
        position={`${pos.x} ${pos.y} -3`}
        geometry="primitive: plane; width: 1.2; height: 0.9"
        material={`color: ${active === idx ? '#555' : '#222'}`}
        scale={active === idx ? '1.4 1.4 1' : '1 1 1'}
        ref={planeRef}
        onClick={handleClick}
      >
        {/* Status overlay */}
        {status && status !== 'ready' && (
          <a-text
            value={status}
            color="#FFF"
            align="center"
            width="1.2"
            position="0 0 0.02"
          />
        )}
        
        {/* Connection status indicator */}
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
      {status && status !== 'ready' && (
        <a-text
          value={status}
          color="#FFF"
          align="center"
          width="1.2"
          position="0 0 0.02"
        ></a-text>
      )}
    </a-entity>
  );
}

export default function VRScene({ onExit }) {
  const [instances, setInstances] = useState([]);
  const [active, setActive] = useState(0);
  const [volumes, setVolumes] = useState([]);
  const [info, setInfo] = useState('');
  const [status, setStatus] = useState({});

  useEffect(() => {
    fetch('/api/config/instances')
      .then((r) => r.json())
      .then((data) => {
        if (Array.isArray(data) && data.length) {
          setInstances(data);
          setVolumes(new Array(data.length).fill(1));
        } else {
          throw new Error('no data');
        }
      })
      .catch(() => {
        setInstances(
          Array.from({ length: 3 }, (_, i) => ({ id: `placeholder-${i}` }))
        );
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

  useEffect(() => {
    const handler = (e) => {
      console.log('KVM event to tile', active + 1, e.key);
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [active]);

  const cols = Math.ceil(Math.sqrt(instances.length || 1));
  const rows = Math.ceil((instances.length || 1) / cols);

  return (
    <div className="w-full h-full relative">
      <div className="absolute top-4 left-4 text-white z-10 font-sans text-sm">
        Active tile: {active + 1} <span className="text-gray-400">{info}</span>
      </div>
      <div className="absolute top-4 right-4 z-10">
        <button
          onClick={onExit}
          className="bg-yellow-500 text-black px-3 py-1 rounded"
        >
          Exit VR
        </button>
      </div>
      <div className="absolute bottom-4 left-4 z-10">
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
        />
      </div>
      <a-scene embedded>
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
              volumes={volumes}
              setVolumes={setVolumes}
              status={status[inst.id]}
            />
          ))}
        </a-entity>
        <a-sky color="#111"></a-sky>
      </a-scene>
    </div>
  );
}
