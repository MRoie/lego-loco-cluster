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
    <div className="min-h-screen lego-background text-black relative">
      {!vrMode && (
        <>
          {/* Header */}
          <div className="lego-header p-4 md:p-6">
            <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between max-w-7xl mx-auto gap-4 sm:gap-0">
              <div>
                <h1 className="text-2xl md:text-3xl font-bold text-white lego-title">
                  🎮 LEGO LOCO CLUSTER
                </h1>
                <p className="text-red-100 text-sm mt-1 lego-text">
                  {displayInstances.length} of {instances.length} instances
                  {showOnlyProvisioned ? ' (provisioned only)' : ''}
                </p>
              </div>
              <div className="flex items-center space-x-2 md:space-x-4 flex-wrap gap-2">
                <button
                  onClick={() => setShowOnlyProvisioned(!showOnlyProvisioned)}
                  className={`px-4 py-2 lego-button lego-text text-sm ${
                    showOnlyProvisioned 
                      ? '' 
                      : 'opacity-70 hover:opacity-100'
                  }`}
                >
                  {showOnlyProvisioned ? 'Show All' : 'Provisioned Only'}
                </button>
                <button
                  onClick={() => setVrMode(true)}
                  className="bg-yellow-400 text-black px-6 py-2 border-2 border-yellow-500 rounded-lg font-bold hover:bg-yellow-300 transition-all duration-200 lego-text shadow-lg"
                  style={{
                    boxShadow: '0 3px 0 #F59E0B, 0 6px 8px rgba(0, 0, 0, 0.2)',
                    transform: 'translateY(0)'
                  }}
                  onMouseDown={(e) => e.target.style.transform = 'translateY(1px)'}
                  onMouseUp={(e) => e.target.style.transform = 'translateY(0)'}
                  onMouseLeave={(e) => e.target.style.transform = 'translateY(0)'}
                >
                  Enter VR
                </button>
              </div>
            </div>
          </div>

          {/* 3x3 Grid Container */}
          <div className="lego-grid-container">
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 md:gap-8 lg:gap-10 max-w-7xl mx-auto w-full">
              {gridInstances.map((instance, index) => (
                <motion.div 
                  key={index} 
                  className="aspect-video"
                  initial={{ opacity: 0, y: 20 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ delay: index * 0.1, duration: 0.5 }}
                >
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
                      className="w-full h-full lego-empty-slot flex items-center justify-center text-gray-600 lego-shimmer cursor-pointer"
                      whileHover={{ 
                        scale: 1.02,
                        y: -2 
                      }}
                      whileTap={{ scale: 0.98 }}
                    >
                      <div className="text-center">
                        <motion.div 
                          className="w-16 h-16 border-3 border-gray-400 rounded-lg mx-auto mb-3 flex items-center justify-center bg-white/50"
                          whileHover={{ borderColor: '#0055BF' }}
                        >
                          <span className="text-3xl text-gray-500">➕</span>
                        </motion.div>
                        <p className="text-sm font-bold lego-text mb-1 text-gray-700">Empty Slot</p>
                        <p className="text-xs lego-text text-gray-600">
                          {showOnlyProvisioned ? 'No provisioned instance' : 'Available for deployment'}
                        </p>
                      </div>
                    </motion.div>
                  )}
                </motion.div>
              ))}
            </div>
          </div>

          {/* Status Bar */}
          <div className="fixed bottom-0 left-0 right-0 lego-status-bar p-3 md:p-4">
            <div className="flex flex-col sm:flex-row items-center justify-between max-w-7xl mx-auto gap-2 sm:gap-0">
              <div className="flex items-center space-x-4">
                <span className="text-sm text-red-100 lego-text">Active Instance:</span>
                <span className="text-sm font-bold text-yellow-300 lego-text">
                  {displayInstances[active]?.id || 'None'}
                </span>
              </div>
              <div className="flex items-center space-x-4 md:space-x-8">
                <div className="flex items-center space-x-2">
                  <div className="w-3 h-3 lego-status-ready rounded-sm"></div>
                  <span className="text-xs text-red-100 lego-text">Ready ({displayInstances.filter(i => i?.status === 'ready').length})</span>
                </div>
                <div className="flex items-center space-x-2">
                  <div className="w-3 h-3 lego-status-booting rounded-sm"></div>
                  <span className="text-xs text-red-100 lego-text">Booting ({displayInstances.filter(i => i?.status === 'booting').length})</span>
                </div>
                <div className="flex items-center space-x-2">
                  <div className="w-3 h-3 lego-status-error rounded-sm"></div>
                  <span className="text-xs text-red-100 lego-text">Error ({displayInstances.filter(i => i?.status === 'error').length})</span>
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
