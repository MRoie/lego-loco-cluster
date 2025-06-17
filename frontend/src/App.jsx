import React, { useEffect, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import VRScene from "./VRScene";
import StreamTile from "./components/StreamTile";


// Main dashboard component showing the 3×3 grid of instances
export default function App() {
  const [instances, setInstances] = useState([]);
  const [hotkeys, setHotkeys] = useState({});
  const [active, setActive] = useState(0);
  const [zoom, setZoom] = useState(1);
  const [vrMode, setVrMode] = useState(false);
  const [status, setStatus] = useState({});
  const [focused, setFocused] = useState(null);

  // Fetch instance list and hotkey mapping from the backend
  useEffect(() => {
    fetch("/api/instances")
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

  useEffect(() => {
    const releaseHandler = (e) => {
      const idx = instances.findIndex((i) => i.id === e.detail.instanceId);
      if (idx === focused) setFocused(null);
    };
    window.addEventListener("vncControlReleased", releaseHandler);
    return () => window.removeEventListener("vncControlReleased", releaseHandler);
  }, [focused, instances]);

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
          <div className="grid gap-4 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 w-full h-full p-4">
            {instances.map((inst, idx) => (
              <StreamTile
                key={inst.id}
                inst={inst}
                idx={idx}
                active={active}
                setActive={setActive}
                zoom={zoom}
                status={status[inst.id]}
                focused={focused}
                setFocused={setFocused}
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
