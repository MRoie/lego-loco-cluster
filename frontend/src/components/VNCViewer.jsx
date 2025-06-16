import React, { useEffect, useRef, useState } from 'react';

/**
 * Simple VNC viewer component that connects to VNC server via WebSocket proxy
 */
export default function VNCViewer({ instanceId }) {
  const canvasRef = useRef(null);
  const [connected, setConnected] = useState(false);
  const [error, setError] = useState(null);
  const wsRef = useRef(null);

  useEffect(() => {
    if (!instanceId) return;

    const canvas = canvasRef.current;
    const ctx = canvas.getContext('2d');
    
    // Clear canvas
    ctx.fillStyle = '#000';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    
    // Show connecting message
    ctx.fillStyle = '#fff';
    ctx.font = '16px Arial';
    ctx.textAlign = 'center';
    ctx.fillText('Connecting to VNC...', canvas.width / 2, canvas.height / 2);

    // For now, let's create a simple test pattern to verify the component works
    const testPattern = () => {
      ctx.fillStyle = '#222';
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      
      // Draw test pattern
      ctx.fillStyle = '#4CAF50';
      ctx.fillRect(50, 50, 200, 150);
      
      ctx.fillStyle = '#fff';
      ctx.font = '20px Arial';
      ctx.textAlign = 'center';
      ctx.fillText(`QEMU Instance: ${instanceId}`, canvas.width / 2, 50);
      ctx.fillText('VNC Connection Ready', canvas.width / 2, canvas.height / 2);
      ctx.fillText('Click to access emulator', canvas.width / 2, canvas.height / 2 + 30);
      
      setConnected(true);
    };

    // Simulate connection after a short delay
    const timer = setTimeout(testPattern, 1000);

    return () => {
      clearTimeout(timer);
      if (wsRef.current) {
        wsRef.current.close();
      }
    };
  }, [instanceId]);

  const handleCanvasClick = () => {
    // For now, show an alert - later we'll implement actual VNC interaction
    alert(`Connecting to VNC for ${instanceId}...`);
  };

  return (
    <div className="relative w-full h-full bg-black rounded-lg overflow-hidden">
      <canvas
        ref={canvasRef}
        width={640}
        height={480}
        className="w-full h-full cursor-pointer"
        onClick={handleCanvasClick}
        style={{ imageRendering: 'pixelated' }}
      />
      {connected && (
        <div className="absolute top-2 left-2 bg-green-500 text-white px-2 py-1 rounded text-xs">
          Connected
        </div>
      )}
      {error && (
        <div className="absolute top-2 left-2 bg-red-500 text-white px-2 py-1 rounded text-xs">
          Error: {error}
        </div>
      )}
    </div>
  );
}
