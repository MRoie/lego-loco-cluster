import React from 'react';
import { motion } from 'framer-motion';
import ReactVNCViewer from './ReactVNCViewer';
import TileControls from './TileControls';
import { createLogger } from '../utils/logger.js';

/**
 * VNC streaming tile displaying a single instance.
 * Handles focus/zoom interactions and shows overlay controls.
 *
 * Props:
 * - inst: instance metadata containing at least an `id`
 * - idx: index of this tile in the grid
 * - active: currently active tile index
 * - setActive: callback to set active tile
 * - zoom: zoom factor for active tile
 * - status: connection status string
 * - focused: index of tile currently fullscreen
 * - setFocused: callback to update focused tile
 */
export default function StreamTile({ inst, idx, active, setActive, zoom, status, focused, setFocused }) {
  const logger = createLogger('StreamTile');
  
  const toggleFullscreen = () => {
    const element = document.querySelector(`[data-instance="${inst.id}"]`);
    if (!element) return;
    if (document.fullscreenElement) {
      document.exitFullscreen().catch((e) => logger.error('exitFullscreen failed', { instanceId: inst.id, error: e.message }));
    } else {
      element.requestFullscreen().catch((e) => logger.error('requestFullscreen failed', { instanceId: inst.id, error: e.message }));
    }
  };

  return (
    <motion.div
      key={inst.id}
      data-instance={inst.id}
      className={`group border-[12px] rounded-2xl border-yellow-500 lego-style transition-transform bg-black overflow-hidden ${active === idx ? 'ring-4 ring-blue-400' : ''} ${focused === idx ? 'fixed inset-0 z-50 w-screen h-screen' : ''}`}
      onClick={() => {
        setActive(idx);
        setFocused(idx);
      }}
      animate={{ scale: active === idx ? zoom + 0.1 : 1 }}
      transition={{ type: 'spring', stiffness: 300 }}
    >
      <ReactVNCViewer instanceId={inst.id} />
      {status && status !== 'ready' && (
        <div className="absolute inset-0 flex items-center justify-center bg-black bg-opacity-50 text-white text-sm">
          {status}
        </div>
      )}
      <TileControls onToggleFullscreen={toggleFullscreen} />
    </motion.div>
  );
}
