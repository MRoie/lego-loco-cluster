import React, { useEffect, useRef, useState, forwardRef, useImperativeHandle } from 'react';

/**
 * VR-compatible NoVNC viewer that exposes canvas for texture mapping
 * Uses NoVNC library for robust VNC protocol implementation
 */
const VRNoVNCViewer = forwardRef(({ instanceId, onConnect, onDisconnect }, ref) => {
  const containerRef = useRef(null);
  const rfbRef = useRef(null);
  const [connected, setConnected] = useState(false);
  const [connecting, setConnecting] = useState(false);
  const [RFB, setRFB] = useState(null);

  // Load NoVNC RFB class dynamically to avoid top-level await issues
  useEffect(() => {
    const loadNoVNC = async () => {
      try {
        console.log('Loading NoVNC RFB module for VR...');
        const novncModule = await import('@novnc/novnc/lib/rfb.js');
        const RFBClass = novncModule.default || novncModule.RFB;
        setRFB(() => RFBClass);
        console.log('NoVNC RFB module loaded successfully for VR');
      } catch (err) {
        console.error('Failed to load NoVNC for VR:', err);
      }
    };
    
    loadNoVNC();
  }, []);

  // Expose canvas and connection methods to parent
  useImperativeHandle(ref, () => ({
    getCanvas: () => {
      // Get the canvas created by NoVNC
      const canvas = containerRef.current?.querySelector('canvas');
      return canvas;
    },
    getConnectionState: () => ({ connected, connecting }),
    sendKey: (key, pressed) => {
      if (rfbRef.current && connected) {
        try {
          // Use NoVNC's sendKey method
          const keySym = getKeySymbol({ key, code: key });
          if (keySym > 0) {
            rfbRef.current.sendKey(keySym, 'Key' + key, pressed);
          }
          console.log(`VR NoVNC: Send key ${key} ${pressed ? 'down' : 'up'}`);
        } catch (error) {
          console.error('Error sending VR key event:', error);
        }
      }
    },
    sendMouse: (x, y, mask) => {
      if (rfbRef.current && connected) {
        try {
          // Use NoVNC's sendPointerEvent method
          rfbRef.current.sendPointerEvent(x, y, mask);
          console.log(`VR NoVNC: Send mouse ${x},${y} mask:${mask}`);
        } catch (error) {
          console.error('Error sending VR pointer event:', error);
        }
      }
    },
    disconnect: () => {
      if (rfbRef.current) {
        rfbRef.current.disconnect();
      }
    }
  }), [connected, connecting]);

  // Key symbol mapping for VR compatibility
  const getKeySymbol = (event) => {
    const key = event.key;
    
    // Handle printable characters
    if (key.length === 1) {
      return key.charCodeAt(0);
    }
    
    // Handle special keys
    const specialKeys = {
      'ArrowUp': 0xff52,
      'ArrowDown': 0xff54,
      'ArrowLeft': 0xff51,
      'ArrowRight': 0xff53,
      'Enter': 0xff0d,
      'Backspace': 0xff08,
      'Delete': 0xffff,
      'Tab': 0xff09,
      'Escape': 0xff1b,
      'Space': 0x0020,
      'Control': 0xffe3,
      'Alt': 0xffe9,
      'Shift': 0xffe1,
    };
    
    return specialKeys[key] || 0;
  };

  useEffect(() => {
    if (!instanceId || !containerRef.current || !RFB) return;

    console.log('Starting VR NoVNC connection for instance:', instanceId);
    setConnecting(true);

    // Clear previous RFB instance
    if (rfbRef.current) {
      rfbRef.current.disconnect();
      rfbRef.current = null;
    }

    // Clear container
    const container = containerRef.current;
    container.innerHTML = '';

    // Create WebSocket connection URL
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const vncUrl = `${protocol}//${window.location.host}/proxy/vnc/${instanceId}/`;

    try {
      // Create RFB instance (noVNC)
      const rfb = new RFB(container, vncUrl, {
        credentials: { password: '' },
        wsProtocols: ['binary'],
        repeaterID: '',
        shared: true
      });

      rfbRef.current = rfb;

      // Event handlers
      rfb.addEventListener('connect', () => {
        console.log('VR NoVNC connected to', instanceId);
        setConnected(true);
        setConnecting(false);
        
        // Trigger onConnect callback with canvas for VR texture mapping
        const canvas = container.querySelector('canvas');
        if (onConnect && canvas) {
          onConnect(instanceId, canvas);
        }
      });

      rfb.addEventListener('disconnect', (e) => {
        console.log('VR NoVNC disconnected:', e.detail);
        setConnected(false);
        setConnecting(false);
        
        if (onDisconnect) {
          onDisconnect(instanceId, e);
        }
      });

      rfb.addEventListener('credentialsrequired', () => {
        console.log('VR NoVNC credentials required');
        setConnecting(false);
      });

      rfb.addEventListener('securityfailure', (e) => {
        console.error('VR NoVNC security failure:', e.detail);
        setConnecting(false);
      });

      // Configure noVNC options for VR use
      rfb.scaleViewport = false;
      rfb.resizeSession = false;
      rfb.showDotCursor = false; // Disable cursor for VR
      rfb.background = '#000000';
      rfb.qualityLevel = 6;
      rfb.compressionLevel = 2;

    } catch (err) {
      console.error('Failed to create VR NoVNC RFB:', err);
      setConnecting(false);
    }

    // Cleanup function
    return () => {
      if (rfbRef.current) {
        rfbRef.current.disconnect();
        rfbRef.current = null;
      }
      setConnected(false);
      setConnecting(false);
    };
  }, [instanceId, RFB]);

  return (
    <div className="w-full h-full bg-black" style={{ display: 'none' }}>
      {/* Hidden container for NoVNC - canvas will be extracted for VR texture */}
      <div
        ref={containerRef}
        style={{ width: '640px', height: '480px' }}
      />
    </div>
  );
});

VRNoVNCViewer.displayName = 'VRNoVNCViewer';

export default VRNoVNCViewer;
