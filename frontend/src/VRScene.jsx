import 'aframe';
import React, { useEffect, useState, useRef } from 'react';
import useWebRTC from './hooks/useWebRTC';

const placeholder = 'https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4';

function positionForIndex(i, cols, rows) {
  const x = (i % cols) - (cols - 1) / 2;
  const row = Math.floor(i / cols);
  const y = (rows - 1) / 2 - row;
  return { x: x * 1.4, y: y * 1.0 };
}

function VRTile({ inst, idx, active, setActive, cols, rows, volumes, setVolumes, status }) {
  const { videoRef } = useWebRTC(inst.id);
  const [fallback, setFallback] = useState(false);

  useEffect(() => {
    const v = videoRef.current;
    if (!v) return;
    v.setAttribute('src', fallback ? placeholder : inst.streamUrl || placeholder);
    v.loop = true;
    v.crossOrigin = 'anonymous';
    v.play().catch(() => {});
    v.onerror = () => {
      setFallback(true);
    };
  }, [videoRef, inst, fallback]);

  useEffect(() => {
    const v = videoRef.current;
    if (v) v.volume = volumes[idx];
  }, [volumes[idx]]);

  const pos = positionForIndex(idx, cols, rows);

  return (
    <a-entity
      class="tile"
      position={`${pos.x} ${pos.y} -3`}
      geometry="primitive: plane; width: 1.2; height: 0.9"
      material={`color: ${active === idx ? '#555' : '#222'}`}
      scale={active === idx ? '1.4 1.4 1' : '1 1 1'}
      onClick={() => setActive(idx)}
    >
      <a-video
        ref={videoRef}
        width="1.2"
        height="0.9"
        position="0 0 0.01"
      ></a-video>
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
