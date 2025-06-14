import React, { useEffect, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import useWebRTC from "./hooks/useWebRTC";
import VRScene from "./VRScene";

function StreamTile({ inst, idx, active, setActive, zoom, status }) {
  const { videoRef, audioLevel } = useWebRTC(inst.id);
  const [muted, setMuted] = useState(true);
  const [volume, setVolume] = useState(1);

  useEffect(() => {
    if (videoRef.current) {
      videoRef.current.muted = muted;
      videoRef.current.volume = volume;
    }
  }, [muted, volume]);

  const toggleFullscreen = () => {
    const el = videoRef.current;
    if (!el) return;
    if (document.fullscreenElement) {
      document
        .exitFullscreen()
        .catch((e) => console.error("exitFullscreen failed", e));
    } else {
      el
        .requestFullscreen()
        .catch((e) => console.error("requestFullscreen failed", e));
    }
  };

  return (
    <motion.div
      key={inst.id}
      className={`border-[12px] rounded-2xl border-yellow-500 lego-style transition-transform bg-black overflow-hidden ${active === idx ? "ring-4 ring-blue-400" : ""}`}
      onClick={() => setActive(idx)}
      animate={{ scale: active === idx ? zoom + 0.1 : 1 }}
      transition={{ type: "spring", stiffness: 300 }}
    >
      <video ref={videoRef} className="w-full h-full" playsInline />
      {status && status !== 'ready' && (
        <div className="absolute inset-0 flex items-center justify-center bg-black bg-opacity-50 text-white text-sm">
          {status}
        </div>
      )}
      <div className="absolute bottom-2 left-2 h-2 bg-gray-700" style={{ width: "80%", position: "absolute" }}>
        <div className="h-full bg-green-500" style={{ width: `${Math.round(audioLevel * 100)}%` }} />
      </div>
      <div className="absolute top-2 right-2 bg-black bg-opacity-50 p-1 rounded flex items-center space-x-2">
        <button
          onClick={(e) => {
            e.stopPropagation();
            setMuted((m) => !m);
          }}
          className="text-white text-xs px-1 border border-white rounded"
        >
          {muted ? "Unmute" : "Mute"}
        </button>
        <input
          type="range"
          min="0"
          max="1"
          step="0.01"
          value={volume}
          onChange={(e) => setVolume(parseFloat(e.target.value))}
        />
        <button
          onClick={(e) => {
            e.stopPropagation();
            toggleFullscreen();
          }}
          className="text-white text-xs px-1 border border-white rounded"
        >
          Full
        </button>
      </div>
    </motion.div>
  );
}

// Main dashboard component showing the 3×3 grid of instances
export default function App() {
  const [instances, setInstances] = useState([]);
  const [hotkeys, setHotkeys] = useState({});
  const [active, setActive] = useState(0);
  const [zoom, setZoom] = useState(1);
  const [vrMode, setVrMode] = useState(false);
  const [status, setStatus] = useState({});

  // Fetch instance list and hotkey mapping from the backend
  useEffect(() => {
    fetch("/api/config/instances")
      .then((r) => r.json())
      .then(setInstances)
      .catch((e) => console.error("Failed to fetch instances", e));
    fetch("/api/config/hotkeys")
      .then((r) => r.json())
      .then(setHotkeys)
      .catch((e) => console.error("Failed to fetch hotkeys", e));
    const interval = setInterval(() => {
      fetch("/api/status")
        .then((r) => r.json())
        .then(setStatus)
        .catch(() => {});
    }, 5000);
    fetch("/api/status").then((r) => r.json()).then(setStatus).catch(() => {});
    return () => clearInterval(interval);
  }, []);

  // Register global hotkeys for focus, zoom and switching instances
  useEffect(() => {
    function handler(e) {
      const parts = [];
      if (e.ctrlKey) parts.push("Ctrl");
      if (e.altKey) parts.push("Alt");
      if (e.shiftKey) parts.push("Shift");
      const key = e.key.length === 1 ? e.key : e.key;
      parts.push(key);
      const combo = parts.join("+");
      if (hotkeys.focus && hotkeys.focus[combo]) {
        const id = hotkeys.focus[combo];
        const idx = instances.findIndex((i) => i.id === id);
        if (idx >= 0) setActive(idx);
      } else if (hotkeys.zoom && hotkeys.zoom[combo]) {
        if (hotkeys.zoom[combo] === "zoom-in")
          setZoom((z) => Math.min(z + 0.1, 2));
        if (hotkeys.zoom[combo] === "zoom-out")
          setZoom((z) => Math.max(z - 0.1, 0.5));
      } else if (hotkeys.switch && hotkeys.switch[combo]) {
        if (hotkeys.switch[combo] === "next-instance") {
          setActive((a) => (a + 1) % instances.length);
        }
      }
    }
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [hotkeys, instances]);

  return (
    <div className="min-h-screen bg-gray-900 flex items-center justify-center relative">
      {!vrMode && (
        <>
          <button
            onClick={() => setVrMode(true)}
            className="absolute top-4 right-4 z-10 bg-yellow-500 text-black px-3 py-1 rounded"
          >
            Enter VR
          </button>
          <div className="grid grid-cols-3 gap-6 w-[90vw] h-[90vh]">
            {instances.map((inst, idx) => (
              <StreamTile
                key={inst.id}
                inst={inst}
                idx={idx}
                active={active}
                setActive={setActive}
                zoom={zoom}
                status={status[inst.id]}
              />
            ))}
          </div>
        </>
      )}
      <AnimatePresence>
        {vrMode && (
          <motion.div
            className="absolute inset-0 bg-black"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
          >
            <VRScene onExit={() => setVrMode(false)} />
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
