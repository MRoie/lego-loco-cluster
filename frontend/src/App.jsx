import React, { useEffect, useState } from "react";
import { motion } from "framer-motion";
import useWebRTC from "./hooks/useWebRTC";

// Main dashboard component showing the 3×3 grid of instances
export default function App() {
  const [instances, setInstances] = useState([]);
  const [hotkeys, setHotkeys] = useState({});
  const [active, setActive] = useState(0);
  const [zoom, setZoom] = useState(1);

  // Fetch instance list and hotkey mapping from the backend
  useEffect(() => {
    fetch("/api/config/instances")
      .then((r) => r.json())
      .then(setInstances)
      .catch(() => {});
    fetch("/api/config/hotkeys")
      .then((r) => r.json())
      .then(setHotkeys)
      .catch(() => {});
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
    <div className="min-h-screen bg-gray-900 flex items-center justify-center">
      <div className="grid grid-cols-3 gap-6 w-[90vw] h-[90vh]">
        {instances.map((inst, idx) => {
          // Each instance establishes its own WebRTC connection
          const { videoRef, audioLevel } = useWebRTC(inst.id);
          return (
            <motion.div
              key={inst.id}
              className={`border-[12px] rounded-2xl border-yellow-500 lego-style transition-transform bg-black overflow-hidden ${active === idx ? "ring-4 ring-blue-400" : ""}`}
              onClick={() => setActive(idx)}
              animate={{ scale: active === idx ? zoom + 0.1 : 1 }}
              transition={{ type: "spring", stiffness: 300 }}
            >
              <video
                ref={videoRef}
                className="w-full h-full"
                muted
                playsInline
              />
              <div
                className="absolute bottom-2 left-2 h-2 bg-gray-700"
                style={{ width: "80%", position: "absolute" }}
              >
                <div
                  className="h-full bg-green-500"
                  style={{ width: `${Math.round(audioLevel * 100)}%` }}
                />
              </div>
            </motion.div>
          );
        })}
      </div>
    </div>
  );
}
