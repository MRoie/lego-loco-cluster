import React, { useEffect, useState } from "react";
import { useActive } from "./ActiveContext";
import { motion, AnimatePresence } from "framer-motion";
import VRScene from "./VRScene";
import InstanceCard from "./components/InstanceCard";
import DiscoveryStatus from "./components/DiscoveryStatus";


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
  const [showOnlyProvisioned, setShowOnlyProvisioned] = useState(false);

  const postActive = (id) => {
    setActiveIds([id]);
  };

  // Fetch instance list and hotkey mapping from the backend
  useEffect(() => {
    const loadInstances = () => {
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
    };

    // Initial load
    loadInstances();
    
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
    
    // Listen for discovery refresh events
    const handleDiscoveryRefresh = () => {
      console.log('Discovery refreshed, reloading instances');
      loadInstances();
    };
    
    window.addEventListener('discoveryRefreshed', handleDiscoveryRefresh);
    
    return () => {
      clearInterval(interval);
      window.removeEventListener('discoveryRefreshed', handleDiscoveryRefresh);
    };
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
  
  // Create a 3x3 grid array with mixed states for demonstration
  const createDemoInstances = () => {
    // If no real instances, show demo states
    if (displayInstances.length === 0) {
      return [
        { id: 'demo-0', name: 'MARY', status: 'ready', provisioned: true, ready: true },
        { id: 'demo-1', name: 'PETER', status: 'running', provisioned: true, ready: true },
        { id: 'demo-2', name: 'LUCY', status: 'booting', provisioned: true, ready: false },
        { id: 'demo-3', name: 'JOHNNY', status: 'error', provisioned: true, ready: false },
        { id: 'demo-4', name: 'FRANK', status: 'ready', provisioned: false, ready: false },
        { id: 'demo-5', name: 'ANNA', status: 'unknown', provisioned: true, ready: false },
        null, // Empty slot
        null, // Empty slot  
        null  // Empty slot
      ];
    }
    
    // Use real instances if available
    const gridInstances = Array(9).fill(null);
    displayInstances.slice(0, 9).forEach((instance, index) => {
      gridInstances[index] = instance;
    });
    return gridInstances;
  };
  
  const gridInstances = createDemoInstances();

  return (
    <div className="min-h-screen lego-background text-black relative">
      {!vrMode && (
        <>
          {/* Transparent Header with VR Button */}
          <div className="absolute top-0 right-0 z-10 p-4">
            <div className="flex items-center space-x-4">
              {/* Discovery Status */}
              <DiscoveryStatus />
              {/* VR Button */}
              <button
                onClick={() => setVrMode(true)}
                className="lego-vr-button"
                title="Enter VR Mode"
              >
                {/* VR Headset Icon */}
                <svg 
                  width="24" 
                  height="24" 
                  viewBox="0 0 24 24" 
                  fill="currentColor"
                  className="w-6 h-6"
                >
                  <path d="M20 8v8a3 3 0 01-3 3h-2.5l-1.5-2H8l-1.5 2H4a3 3 0 01-3-3V8a3 3 0 013-3h13a3 3 0 013 3zM6.5 13.5a1.5 1.5 0 100-3 1.5 1.5 0 000 3zm11 0a1.5 1.5 0 100-3 1.5 1.5 0 000 3z"/>
                </svg>
              </button>
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
