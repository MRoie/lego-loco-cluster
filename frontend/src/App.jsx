import React, { useEffect, useState } from "react";
import { useActive } from "./ActiveContext";
import { motion, AnimatePresence } from "framer-motion";
import VRScene from "./VRScene";
import InstanceCard from "./components/InstanceCard";


// Main dashboard component showing the 3×3 grid of instances
export default function App() {
  const { activeIds, setActiveIds } = useActive();
  const [instances, setInstances] = useState([]);
  const [provisionedInstances, setProvisionedInstances] = useState([]);
  const [hotkeys, setHotkeys] = useState({});
  const [active, setActive] = useState(0);
  const [zoom, setZoom] = useState(1);
  const defaultVr = import.meta.env.VITE_DEFAULT_VR === 'true';
  const [vrMode, setVrMode] = useState(defaultVr);
  const [status, setStatus] = useState({});
  const [focused, setFocused] = useState(null);
  const [showOnlyProvisioned, setShowOnlyProvisioned] = useState(true);

  const postActive = (id) => {
    setActiveIds([id]);
  };

  // Fetch instance list and hotkey mapping from the backend
  useEffect(() => {
    // Load all instances
    fetch("/api/instances")
      .then((r) => r.json())
      .then(setInstances)
      .catch((e) => console.error("Failed to fetch instances", e));
    
    // Load only provisioned instances
    fetch("/api/instances/provisioned")
      .then((r) => r.json())
      .then(setProvisionedInstances)
      .catch((e) => console.error("Failed to fetch provisioned instances", e));
    
    fetch("/api/config/hotkeys")
      .then((r) => r.json())
      .then(setHotkeys)
      .catch((e) => console.error("Failed to fetch hotkeys", e));
    
    const interval = setInterval(() => {
      fetch("/api/status")
        .then((r) => r.json())
        .then(setStatus)
        .catch(() => {});
      
      // Refresh provisioned instances periodically
      fetch("/api/instances/provisioned")
        .then((r) => r.json())
        .then(setProvisionedInstances)
        .catch(() => {});
    }, 5000);
    
    fetch("/api/status").then((r) => r.json()).then(setStatus).catch(() => {});
    return () => clearInterval(interval);
  }, []);

  // Update active index when activeIds or instances change
  useEffect(() => {
    if (!activeIds.length || instances.length === 0) return;
    const idx = instances.findIndex((i) => i.id === activeIds[0]);
    if (idx >= 0) setActive(idx);
  }, [activeIds, instances]);

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
      
      const currentInstances = showOnlyProvisioned ? provisionedInstances : instances;
      
      if (hotkeys.focus && hotkeys.focus[combo]) {
        const id = hotkeys.focus[combo];
        const idx = currentInstances.findIndex((i) => i.id === id);
        if (idx >= 0) {
          setActive(idx);
          postActive(currentInstances[idx].id);
        }
      } else if (hotkeys.zoom && hotkeys.zoom[combo]) {
        if (hotkeys.zoom[combo] === "zoom-in")
          setZoom((z) => Math.min(z + 0.1, 2));
        if (hotkeys.zoom[combo] === "zoom-out")
          setZoom((z) => Math.max(z - 0.1, 0.5));
      } else if (hotkeys.switch && hotkeys.switch[combo]) {
        if (hotkeys.switch[combo] === "next-instance") {
          const next = (active + 1) % currentInstances.length;
          setActive(next);
          postActive(currentInstances[next].id);
        }
      }
    }
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [hotkeys, instances, provisionedInstances, showOnlyProvisioned]);

  useEffect(() => {
    const releaseHandler = (e) => {
      const currentInstances = showOnlyProvisioned ? provisionedInstances : instances;
      const idx = currentInstances.findIndex((i) => i.id === e.detail.instanceId);
      if (idx === focused) setFocused(null);
    };
    window.addEventListener("vncControlReleased", releaseHandler);
    return () => window.removeEventListener("vncControlReleased", releaseHandler);
  }, [focused, instances, provisionedInstances, showOnlyProvisioned]);


  // Get the instances to display based on filter
  const displayInstances = showOnlyProvisioned ? provisionedInstances : instances;
  
  // Create a 3x3 grid array, filling empty slots with null
  const gridInstances = Array(9).fill(null);
  displayInstances.slice(0, 9).forEach((instance, index) => {
    gridInstances[index] = instance;
  });

  return (
    <div className="min-h-screen bg-gray-900 text-white relative">
      {!vrMode && (
        <>
          {/* Header */}
          <div className="bg-gray-800 border-b border-gray-700 p-4">
            <div className="flex items-center justify-between">
              <div>
                <h1 className="text-2xl font-bold text-yellow-400">🎮 Lego Loco Cluster</h1>
                <p className="text-gray-300 text-sm">
                  {displayInstances.length} of {instances.length} instances
                  {showOnlyProvisioned ? ' (provisioned only)' : ''}
                </p>
              </div>
              <div className="flex items-center space-x-4">
                <button
                  onClick={() => setShowOnlyProvisioned(!showOnlyProvisioned)}
                  className={`px-3 py-1 rounded text-sm transition-colors ${
                    showOnlyProvisioned 
                      ? 'bg-blue-600 text-white hover:bg-blue-700' 
                      : 'bg-gray-600 text-gray-300 hover:bg-gray-500'
                  }`}
                >
                  {showOnlyProvisioned ? 'Show All' : 'Provisioned Only'}
                </button>
                <button
                  onClick={() => setVrMode(true)}
                  className="bg-yellow-500 text-black px-4 py-2 rounded font-medium hover:bg-yellow-400 transition-colors"
                >
                  Enter VR
                </button>
              </div>
            </div>
          </div>

          {/* 3x3 Grid Container */}
          <div className="p-6">
            <div className="grid grid-cols-3 gap-6 max-w-6xl mx-auto">
              {gridInstances.map((instance, index) => (
                <div key={index} className="aspect-video">
                  {instance ? (
                    <InstanceCard
                      instance={instance}
                      isActive={active === index}
                      onClick={() => {
                        setActive(index);
                        postActive(displayInstances[index].id);
                      }}
                    />
                  ) : (
                    <motion.div
                      className="w-full h-full border-2 border-dashed border-gray-600 rounded-lg flex items-center justify-center text-gray-500"
                      whileHover={{ borderColor: '#9CA3AF' }}
                    >
                      <div className="text-center">
                        <div className="w-12 h-12 border border-gray-600 rounded-lg mx-auto mb-2 flex items-center justify-center">
                          <span className="text-2xl">➕</span>
                        </div>
                        <p className="text-sm">Empty Slot</p>
                        <p className="text-xs opacity-75">
                          {showOnlyProvisioned ? 'No provisioned instance' : 'Available slot'}
                        </p>
                      </div>
                    </motion.div>
                  )}
                </div>
              ))}
            </div>
          </div>

          {/* Status Bar */}
          <div className="fixed bottom-0 left-0 right-0 bg-gray-800 border-t border-gray-700 p-3">
            <div className="flex items-center justify-between max-w-6xl mx-auto">
              <div className="flex items-center space-x-4">
                <span className="text-sm text-gray-300">Active Instance:</span>
                <span className="text-sm font-medium text-yellow-400">
                  {displayInstances[active]?.id || 'None'}
                </span>
              </div>
              <div className="flex items-center space-x-6">
                <div className="flex items-center space-x-2">
                  <div className="w-2 h-2 bg-green-500 rounded-full"></div>
                  <span className="text-xs text-gray-300">Ready ({displayInstances.filter(i => i?.status === 'ready').length})</span>
                </div>
                <div className="flex items-center space-x-2">
                  <div className="w-2 h-2 bg-yellow-500 rounded-full"></div>
                  <span className="text-xs text-gray-300">Booting ({displayInstances.filter(i => i?.status === 'booting').length})</span>
                </div>
                <div className="flex items-center space-x-2">
                  <div className="w-2 h-2 bg-red-500 rounded-full"></div>
                  <span className="text-xs text-gray-300">Error ({displayInstances.filter(i => i?.status === 'error').length})</span>
                </div>
              </div>
            </div>
          </div>
        </>
      )}
      
      <AnimatePresence>
        {vrMode && (
          <motion.div
            className="fixed inset-0 bg-black z-50"
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
