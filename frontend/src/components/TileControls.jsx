import React, { useState } from 'react';

/**
 * Overlay with per-tile controls.
 * Provides volume, fullscreen and settings toggles for a VNC tile.
 *
 * @param {Object} props Component props
 * @param {function} props.onToggleFullscreen Callback when fullscreen icon is clicked
 */
export default function TileControls({ onToggleFullscreen }) {
  const [muted, setMuted] = useState(true);
  const [volume, setVolume] = useState(1);
  const [hover, setHover] = useState(false);
  const [showDetails, setShowDetails] = useState(false);

  return (
    <div className="absolute top-2 right-2 flex items-center space-x-2">
      <div
        className="relative"
        onMouseEnter={() => setHover(true)}
        onMouseLeave={() => setHover(false)}
      >
        <button
          onClick={(e) => {
            e.stopPropagation();
            setMuted((m) => !m);
          }}
          className="text-white text-xs px-1 bg-black bg-opacity-60 rounded"
        >
          {muted ? '🔇' : '🔊'}
        </button>
        {hover && (
          <div className="absolute right-0 mt-1 bg-black bg-opacity-70 p-2 rounded">
            <input
              type="range"
              min="0"
              max="1"
              step="0.01"
              value={volume}
              onChange={(e) => setVolume(parseFloat(e.target.value))}
            />
          </div>
        )}
      </div>
      <button
        onClick={(e) => {
          e.stopPropagation();
          onToggleFullscreen();
        }}
        className="text-white text-xs px-1 bg-black bg-opacity-60 rounded"
      >
        ⛶
      </button>
      <div className="relative">
        <button
          onClick={(e) => {
            e.stopPropagation();
            setShowDetails((s) => !s);
          }}
          className="text-white text-xs px-1 bg-black bg-opacity-60 rounded"
        >
          ⚙
        </button>
        {showDetails && (
          <div className="absolute right-0 mt-1 bg-gray-800 text-white text-xs p-2 rounded shadow">
            Advanced settings
          </div>
        )}
      </div>
    </div>
  );
}
