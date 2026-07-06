import React, { useEffect, useRef, useState, forwardRef, useImperativeHandle } from 'react';

/**
 * VR-compatible VNC viewer that exposes canvas for texture mapping
 * Simplified implementation without NoVNC dependency
 */
const VRVNCViewer = forwardRef(({ instanceId, onConnect, onDisconnect }, ref) => {
  const canvasRef = useRef(null);
  const wsRef = useRef(null);
  const [connected, setConnected] = useState(false);
  const [connecting, setConnecting] = useState(false);

  // Expose canvas and connection methods to parent
  useImperativeHandle(ref, () => ({
    getCanvas: () => canvasRef.current,
    getConnectionState: () => ({ connected, connecting }),
    sendKey: (key, pressed) => {
      console.log(`VR VNC: Send key ${key} ${pressed ? 'down' : 'up'}`);
      // Key event would be sent to VNC server here
    },
    sendMouse: (x, y, mask) => {
      console.log(`VR VNC: Send mouse ${x},${y} mask:${mask}`);
      // Mouse event would be sent to VNC server here
    },
    disconnect: () => {
      if (wsRef.current) {
        wsRef.current.close();
      }
    }
  }), [connected, connecting]);

  useEffect(() => {
    if (!instanceId) return;

    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    setConnecting(true);

    // Create WebSocket connection to VNC proxy
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const vncUrl = `${protocol}//${window.location.host}/proxy/vnc/${instanceId}/`;

    try {
      const ws = new WebSocket(vncUrl);
      wsRef.current = ws;

      ws.onopen = () => {
        console.log('VR VNC connected to', instanceId);
        setConnected(true);
        setConnecting(false);
        
        // Draw a test pattern on the canvas for VR texture
        ctx.fillStyle = '#1a1a2e';
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        
        // Draw simulated desktop
        ctx.fillStyle = '#008080';
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        
        // Draw title bar
        ctx.fillStyle = '#c0c0c0';
        ctx.fillRect(0, 0, canvas.width, 30);
        ctx.fillStyle = '#000080';
        ctx.fillRect(5, 5, canvas.width - 10, 20);
        
        ctx.fillStyle = '#fff';
        ctx.font = '14px Arial';
        ctx.fillText(`QEMU - ${instanceId}`, 10, 18);
        
        // Draw desktop icons
        for (let i = 0; i < 6; i++) {
          const x = 20 + (i % 3) * 80;
          const y = 50 + Math.floor(i / 3) * 80;
          
          // Icon background
          ctx.fillStyle = '#c0c0c0';
          ctx.fillRect(x, y, 32, 32);
          ctx.fillStyle = '#800080';
          ctx.fillRect(x + 4, y + 4, 24, 24);
          
          // Icon label
          ctx.fillStyle = '#fff';
          ctx.font = '10px Arial';
          ctx.fillText(['Loco', 'Game', 'Files', 'Tools', 'Help', 'Exit'][i], x, y + 45);
        }
        
        // Draw taskbar
        ctx.fillStyle = '#c0c0c0';
        ctx.fillRect(0, canvas.height - 30, canvas.width, 30);
        
        // Start button
        ctx.fillStyle = '#808080';
        ctx.fillRect(5, canvas.height - 25, 50, 20);
        ctx.fillStyle = '#000';
        ctx.font = '12px Arial';
        ctx.fillText('Start', 8, canvas.height - 12);
        
        if (onConnect) onConnect(instanceId);
      };

      ws.onerror = (err) => {
        console.error('VR VNC WebSocket error:', err);
        setConnecting(false);
        setConnected(false);
      };

      ws.onclose = (e) => {
        console.log('VR VNC WebSocket closed:', e.code, e.reason);
        setConnected(false);
        setConnecting(false);
        
        if (onDisconnect) onDisconnect(instanceId, e);
      };

      ws.onmessage = (event) => {
        // Handle VNC protocol messages
        console.log('VR VNC message received:', event.data);
        
        // Update canvas with new frame data here
        // For now, just add a small indicator that data is being received
        if (connected && canvas) {
          const ctx = canvas.getContext('2d');
          ctx.fillStyle = '#00ff00';
          ctx.fillRect(canvas.width - 20, 5, 10, 10);
          setTimeout(() => {
            ctx.fillStyle = '#c0c0c0';
            ctx.fillRect(canvas.width - 20, 5, 10, 10);
          }, 100);
        }
      };

    } catch (err) {
      console.error('Failed to create VR VNC WebSocket:', err);
      setConnecting(false);
    }

    // Cleanup function
    return () => {
      if (wsRef.current) {
        wsRef.current.close();
        wsRef.current = null;
      }
      setConnected(false);
      setConnecting(false);
    };
  }, [instanceId]);

  return (
    <div className="w-full h-full bg-black" style={{ display: 'none' }}>
      {/* Hidden canvas for VR texture extraction */}
      <canvas
        ref={canvasRef}
        width={640}
        height={480}
        style={{ width: '640px', height: '480px' }}
      />
    </div>
  );
});

VRVNCViewer.displayName = 'VRVNCViewer';

export default VRVNCViewer;
