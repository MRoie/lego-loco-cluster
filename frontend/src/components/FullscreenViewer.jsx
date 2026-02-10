import React, { useState, useEffect, useRef } from 'react';
import { motion } from 'framer-motion';
import VNCViewerSwitcher from './VNCViewerSwitcher';
import NoVNCViewer from './NoVNCViewer';
import useWebRTC from '../hooks/useWebRTC';

/**
 * Fullscreen viewer for controlling a single QEMU instance.
 * Hides all obstructions (instructions, overlays) so the user can
 * interact with the Win98 desktop as if it were a native display.
 *
 * Exit: Escape key, or click the small ✕ button in the top-right corner.
 */
export default function FullscreenViewer({ instance, onExit, showBenchmark }) {
  const { videoRef, loading } = useWebRTC(instance.id);
  const [showHud, setShowHud] = useState(true);
  const hudTimerRef = useRef(null);
  const containerRef = useRef(null);

  // Auto-hide HUD after 3 seconds of inactivity
  useEffect(() => {
    const scheduleHide = () => {
      clearTimeout(hudTimerRef.current);
      setShowHud(true);
      hudTimerRef.current = setTimeout(() => setShowHud(false), 3000);
    };

    scheduleHide();

    const handleMouseMove = () => scheduleHide();
    window.addEventListener('mousemove', handleMouseMove);
    return () => {
      window.removeEventListener('mousemove', handleMouseMove);
      clearTimeout(hudTimerRef.current);
    };
  }, []);

  // Request browser fullscreen on mount
  useEffect(() => {
    const el = containerRef.current;
    if (el && el.requestFullscreen) {
      el.requestFullscreen().catch(() => {
        // Browser may deny if not user-gesture driven; that's OK
      });
    }
    return () => {
      if (document.fullscreenElement) {
        document.exitFullscreen().catch(() => {});
      }
    };
  }, []);

  // Listen for fullscreen exit (browser F11 / Escape exits browser fullscreen)
  useEffect(() => {
    const handleFsChange = () => {
      if (!document.fullscreenElement && containerRef.current) {
        // User exited browser fullscreen; we stay in our overlay mode
        // They can press Escape again or click ✕ to close
      }
    };
    document.addEventListener('fullscreenchange', handleFsChange);
    return () => document.removeEventListener('fullscreenchange', handleFsChange);
  }, []);

  const isDemo = instance.id?.startsWith('demo-');
  const isReady = instance.provisioned && (instance.ready || instance.status === 'ready' || instance.status === 'running');

  return (
    <motion.div
      ref={containerRef}
      className="fixed inset-0 z-[100] bg-black flex items-center justify-center"
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      transition={{ duration: 0.2 }}
    >
      {/* VNC / Video content — fills the entire screen */}
      <div className="absolute inset-0">
        {isReady && !isDemo ? (
          <>
            {!loading ? (
              <video
                ref={videoRef}
                className="w-full h-full object-contain bg-black"
                autoPlay
                playsInline
                muted
              />
            ) : (
              <NoVNCViewer instanceId={instance.id} fullscreen />
            )}
          </>
        ) : (
          <div className="w-full h-full flex items-center justify-center text-white text-xl">
            {isDemo ? 'Demo instance — no live VNC' : 'Instance not ready'}
          </div>
        )}
      </div>

      {/* Minimal HUD — auto-hides, reappears on mouse move */}
      <div
        className={`absolute top-0 left-0 right-0 z-[110] transition-opacity duration-300 ${
          showHud ? 'opacity-100' : 'opacity-0 pointer-events-none'
        }`}
      >
        <div className="flex items-center justify-between px-4 py-2 bg-gradient-to-b from-black/70 to-transparent">
          {/* Instance name */}
          <div className="flex items-center space-x-3">
            <div className="w-3 h-3 rounded-full bg-green-400 animate-pulse" />
            <span className="text-white font-mono text-sm font-bold tracking-wide">
              {instance.name || instance.id}
            </span>
            <span className="text-gray-400 font-mono text-xs">
              FULLSCREEN CONTROL
            </span>
          </div>

          {/* Exit button */}
          <div className="flex items-center space-x-3">
            <span className="text-gray-400 text-xs font-mono hidden sm:block">
              ESC to exit
            </span>
            <button
              onClick={onExit}
              className="bg-red-600/80 hover:bg-red-500 text-white w-8 h-8 rounded-full flex items-center justify-center text-lg font-bold transition-colors"
              title="Exit fullscreen (Escape)"
            >
              ✕
            </button>
          </div>
        </div>
      </div>

      {/* Minimal bottom HUD — connection info */}
      <div
        className={`absolute bottom-0 left-0 right-0 z-[110] transition-opacity duration-300 ${
          showHud ? 'opacity-100' : 'opacity-0 pointer-events-none'
        }`}
      >
        <div className="flex items-center justify-between px-4 py-2 bg-gradient-to-t from-black/70 to-transparent">
          <span className="text-gray-400 font-mono text-xs">
            Ctrl+Alt+R to release VNC control
          </span>
          <div className="flex items-center space-x-4 text-xs font-mono">
            <span className="text-green-400">● Connected</span>
            <span className="text-gray-400">{instance.id}</span>
          </div>
        </div>
      </div>
    </motion.div>
  );
}
