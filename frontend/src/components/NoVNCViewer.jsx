import React, { useEffect, useRef, useState } from 'react';

/**
 * NoVNC-based VNC viewer component
 * Uses the noVNC library for robust VNC protocol implementation
 */
export default function NoVNCViewer({ instanceId }) {
  const containerRef = useRef(null);
  const rfbRef = useRef(null);
  const [connected, setConnected] = useState(false);
  const [connecting, setConnecting] = useState(false);
  const [error, setError] = useState(null);
  const [hasControl, setHasControl] = useState(false);
  const [framebufferSize, setFramebufferSize] = useState(null);
  const [RFB, setRFB] = useState(null);
  
  // Control release tracking
  const keySequenceRef = useRef([]);
  const lastKeyTimeRef = useRef(0);

  // Load NoVNC RFB class dynamically to avoid top-level await issues
  useEffect(() => {
    const loadNoVNC = async () => {
      try {
        console.log('Loading NoVNC RFB module...');
        const novncModule = await import('@novnc/novnc/lib/rfb.js');
        const RFBClass = novncModule.default || novncModule.RFB;
        setRFB(() => RFBClass);
        console.log('NoVNC RFB module loaded successfully');
      } catch (err) {
        console.error('Failed to load NoVNC:', err);
        setError(`Failed to load NoVNC: ${err.message}`);
      }
    };
    
    loadNoVNC();
  }, []);

  // Debug logging for hasControl state changes
  useEffect(() => {
    console.log(`🎮 NoVNC hasControl state changed to: ${hasControl} for instance ${instanceId}`);
  }, [hasControl, instanceId]);

  console.log('NoVNCViewer component mounted for instance:', instanceId);

  useEffect(() => {
    if (!instanceId || !containerRef.current || !RFB) {
      console.log('Missing instanceId, container ref, or RFB:', { instanceId, container: !!containerRef.current, RFB: !!RFB });
      return;
    }

    console.log('Starting NoVNC connection for instance:', instanceId);
    setConnecting(true);
    setConnected(false);
    setError(null);
    setHasControl(false);

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
    
    console.log('Connecting to VNC URL:', vncUrl);

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
        console.log('NoVNC connected to', instanceId);
        setConnected(true);
        setConnecting(false);
        setHasControl(true);
        setError(null);
        
        // Get framebuffer size
        const canvas = container.querySelector('canvas');
        if (canvas) {
          setFramebufferSize({ 
            width: canvas.width, 
            height: canvas.height 
          });
        }
      });

      rfb.addEventListener('disconnect', (e) => {
        console.log('NoVNC disconnected:', e.detail);
        setConnected(false);
        setConnecting(false);
        setHasControl(false);
        
        if (!e.detail.clean) {
          setError('Connection lost');
        }
      });

      rfb.addEventListener('credentialsrequired', () => {
        console.log('VNC credentials required');
        setError('VNC server requires authentication');
        setConnecting(false);
      });

      rfb.addEventListener('securityfailure', (e) => {
        console.error('VNC security failure:', e.detail);
        setError('VNC security failure');
        setConnecting(false);
      });

      rfb.addEventListener('bell', () => {
        console.log('VNC bell signal received');
      });

      rfb.addEventListener('desktopname', (e) => {
        console.log('VNC desktop name:', e.detail.name);
      });

      // Configure noVNC options
      rfb.scaleViewport = false;
      rfb.resizeSession = false;
      rfb.showDotCursor = true;
      rfb.background = '#000000';
      rfb.qualityLevel = 6;
      rfb.compressionLevel = 2;

    } catch (err) {
      console.error('Failed to create NoVNC RFB:', err);
      setError(`Connection failed: ${err.message}`);
      setConnecting(false);
    }

    // Cleanup function
    return () => {
      if (rfbRef.current) {
        rfbRef.current.disconnect();
        rfbRef.current = null;
      }
      keySequenceRef.current = [];
      lastKeyTimeRef.current = 0;
      setConnected(false);
      setConnecting(false);
      setHasControl(false);
    };
  }, [instanceId, RFB]);

  // VR Controller Support - Listen for VR events
  useEffect(() => {
    // VR trigger button handler (for regaining control)
    const handleVRTrigger = (event) => {
      if (event.detail.instanceId === instanceId && !hasControl && connected) {
        console.log('🎮 VR trigger detected for control regain');
        regainControl();
      }
    };

    // VR release gesture handler (for releasing control)
    const handleVRRelease = (event) => {
      if (event.detail.instanceId === instanceId && hasControl) {
        console.log('🎮 VR release gesture detected');
        releaseControl();
      }
    };

    // VR input events (pointer/keyboard from VR controllers)
    const handleVRPointer = (event) => {
      if (event.detail.instanceId === instanceId && hasControl && connected && rfbRef.current) {
        const { x, y, button, pressed } = event.detail;
        console.log(`🎮 VR pointer: (${x}, ${y}) button=${button} pressed=${pressed}`);
        
        if (x >= 0 && y >= 0) {
          const buttonMask = pressed ? (1 << button) : 0;
          try {
            rfbRef.current.sendPointerEvent(x, y, buttonMask);
          } catch (error) {
            console.error('Error sending VR pointer event:', error);
          }
        }
      }
    };

    const handleVRKeyboard = (event) => {
      if (event.detail.instanceId === instanceId && hasControl && connected && rfbRef.current) {
        const { key, pressed } = event.detail;
        console.log(`🎮 VR keyboard: key=${key} pressed=${pressed}`);
        
        try {
          // Convert VR key to keySym (basic implementation)
          const keySym = getKeySymbol({ key, code: key });
          if (keySym > 0) {
            rfbRef.current.sendKey(keySym, 'Key' + key, pressed);
          }
        } catch (error) {
          console.error('Error sending VR keyboard event:', error);
        }
      }
    };

    // Add VR event listeners
    window.addEventListener('vrTriggerPress', handleVRTrigger);
    window.addEventListener('vrReleaseGesture', handleVRRelease);
    window.addEventListener('vrPointerEvent', handleVRPointer);
    window.addEventListener('vrKeyboardEvent', handleVRKeyboard);

    // Cleanup VR event listeners
    return () => {
      window.removeEventListener('vrTriggerPress', handleVRTrigger);
      window.removeEventListener('vrReleaseGesture', handleVRRelease);
      window.removeEventListener('vrPointerEvent', handleVRPointer);
      window.removeEventListener('vrKeyboardEvent', handleVRKeyboard);
    };
  }, [instanceId, hasControl, connected]);

  // Keyboard event handler for control release sequences
  useEffect(() => {
    const handleKeyDown = (event) => {
      if (!connected || !hasControl) return;
      
      // Check for control release sequence
      if (checkControlReleaseSequence(event)) {
        console.log('🔓 Control release sequence detected!');
        releaseControl();
        event.preventDefault();
        event.stopPropagation();
        return;
      }
    };

    // Add keyboard event listener to document
    document.addEventListener('keydown', handleKeyDown);
    
    return () => {
      document.removeEventListener('keydown', handleKeyDown);
    };
  }, [connected, hasControl]);

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

  // Control release mechanism - compatible with VR controllers
  const checkControlReleaseSequence = (event) => {
    const now = Date.now();
    const resetTimeout = 3000; // 3 seconds to complete sequence
    
    // Reset sequence if too much time has passed
    if (now - lastKeyTimeRef.current > resetTimeout) {
      keySequenceRef.current = [];
    }
    
    lastKeyTimeRef.current = now;
    
    // Control release sequences
    const releaseSequences = [
      // Primary sequence: Ctrl+Alt+R
      ['Control', 'Alt', 'KeyR'],
      // Alternative: Ctrl+Shift+Escape
      ['Control', 'Shift', 'Escape'],
      // VR-friendly: F10 three times quickly
      ['F10', 'F10', 'F10'],
      // Gaming-friendly: Ctrl+Alt+Q
      ['Control', 'Alt', 'KeyQ']
    ];
    
    // Add current key to sequence
    keySequenceRef.current.push(event.code);
    
    // Keep only last 5 keys
    if (keySequenceRef.current.length > 5) {
      keySequenceRef.current = keySequenceRef.current.slice(-5);
    }
    
    // Check if any release sequence is matched
    for (const sequence of releaseSequences) {
      if (keySequenceRef.current.length >= sequence.length) {
        const lastKeys = keySequenceRef.current.slice(-sequence.length);
        
        // Special handling for F10 triple-tap
        if (sequence.every(key => key === 'F10')) {
          const f10Times = keySequenceRef.current.filter(key => key === 'F10');
          if (f10Times.length >= 3) {
            const recentF10Count = keySequenceRef.current.slice(-6).filter(key => key === 'F10').length;
            if (recentF10Count >= 3) {
              return true;
            }
          }
        } else {
          // Check for exact sequence match
          if (lastKeys.every((key, index) => key === sequence[index])) {
            return true;
          }
        }
      }
    }
    
    return false;
  };

  // Release control of this instance
  const releaseControl = () => {
    console.log('🔓 Releasing control of NoVNC instance:', instanceId);
    setHasControl(false);
    keySequenceRef.current = [];
    
    // Dispatch custom event for VR and other controllers
    const releaseEvent = new CustomEvent('vncControlReleased', {
      detail: { 
        instanceId, 
        timestamp: Date.now(),
        reason: 'keyboard_combo'
      }
    });
    window.dispatchEvent(releaseEvent);
    
    console.log('🎮 Control release event dispatched for VR/external controllers');
  };

  // Regain control of this instance
  const regainControl = () => {
    console.log(`🔒 regainControl called: connected=${connected}, currentControl=${hasControl}`);
    
    if (!connected) {
      console.log('Cannot regain control: VNC not connected');
      return;
    }
    
    console.log('🔒 Regaining control of NoVNC instance:', instanceId);
    setHasControl(true);
    keySequenceRef.current = [];
    
    // Dispatch custom event for VR and other controllers
    const regainEvent = new CustomEvent('vncControlRegained', {
      detail: { 
        instanceId, 
        timestamp: Date.now(),
        method: 'click'
      }
    });
    window.dispatchEvent(regainEvent);
    
    // Focus the NoVNC canvas
    const canvas = containerRef.current?.querySelector('canvas');
    if (canvas) {
      canvas.focus();
      console.log('🎯 Canvas focused for keyboard input');
    }
    
    console.log('🎮 Control regain event dispatched for VR/external controllers');
    console.log(`✅ Control regained successfully: hasControl will be=${true}`);
  };

  const handleReconnect = () => {
    console.log('🔄 handleReconnect called - triggering reconnection');
    setError(null);
    
    // Trigger reconnection by changing a dependency
    setConnecting(true);
  };

  const handleContainerClick = () => {
    if (!connected) {
      console.log('Container clicked - attempting to connect');
      handleReconnect();
      return;
    }
    
    if (!hasControl) {
      console.log('Container clicked - regaining control');
      regainControl();
    }
  };

  return (
    <div className="relative w-full h-full bg-black rounded-lg overflow-hidden">
      {/* NoVNC Display Container */}
      <div
        ref={containerRef}
        className="w-full h-full cursor-pointer"
        onClick={handleContainerClick}
        style={{ 
          outline: 'none',
          userSelect: 'none'
        }}
      />

      {/* Status Indicators */}
      {connecting && (
        <div className="absolute top-2 left-2 bg-blue-500 text-white px-2 py-1 rounded text-xs">
          <div className="animate-pulse">Connecting...</div>
        </div>
      )}

      {connected && (
        <div className="absolute top-2 left-2 bg-green-500 text-white px-2 py-1 rounded text-xs font-semibold">
          <div>NoVNC Connected</div>
          {framebufferSize && (
            <div className="text-xs opacity-90">
              {framebufferSize.width}×{framebufferSize.height}
            </div>
          )}
        </div>
      )}

      {error && (
        <div className="absolute inset-0 flex items-center justify-center bg-black bg-opacity-75">
          <div className="bg-red-600 text-white px-4 py-2 rounded-lg text-center max-w-sm">
            <div className="font-semibold mb-2">Connection Error</div>
            <div className="text-sm mb-3">{error}</div>
            <button 
              onClick={handleReconnect}
              className="bg-red-700 hover:bg-red-800 px-3 py-1 rounded text-sm"
            >
              Retry Connection
            </button>
          </div>
        </div>
      )}

      {/* Control Panel */}
      {connected && (
        <div className="absolute top-2 right-2 bg-black bg-opacity-75 rounded-lg p-2 flex items-center space-x-2 text-white text-xs">
          <span className={hasControl ? "text-green-400" : "text-orange-400"}>●</span>
          <span>{instanceId}</span>
          <span className="text-gray-400">|</span>
          <span className={hasControl ? "text-blue-400" : "text-orange-400"}>
            {hasControl ? "In Control" : "No Control"}
          </span>
          {hasControl && (
            <>
              <span className="text-gray-400">|</span>
              <span className="text-yellow-400 text-xs">Ctrl+Alt+R to release</span>
            </>
          )}
        </div>
      )}

      {/* Input Instructions */}
      {connected && hasControl && (
        <div className="absolute bottom-2 left-2 bg-black bg-opacity-75 rounded-lg p-2 text-white text-xs max-w-xs">
          <div className="font-semibold mb-1">NoVNC Controls:</div>
          <div>• Full mouse and keyboard support via NoVNC</div>
          <div>• Right-click context menu, function keys, special keys</div>
          <div className="mt-2 text-yellow-400">
            <div className="font-semibold">Release Control:</div>
            <div>• Ctrl+Alt+R (primary)</div>
            <div>• Ctrl+Shift+Esc</div>
            <div>• F10 x3 (VR-friendly)</div>
            <div>• Ctrl+Alt+Q</div>
          </div>
        </div>
      )}

      {/* No Control Overlay */}
      {connected && !hasControl && (
        <div className="absolute inset-0 flex items-center justify-center bg-black bg-opacity-50 text-white">
          <div className="text-center bg-orange-600 bg-opacity-90 rounded-lg p-4">
            <div className="text-lg font-semibold mb-2">🔓 No Control</div>
            <div className="text-sm mb-3">Another user may be controlling this instance</div>
            <div className="text-xs mb-3">
              <div>Click to regain control</div>
              <div>VR users: Use trigger button</div>
            </div>
            <button 
              onClick={regainControl}
              className="bg-blue-600 hover:bg-blue-700 px-3 py-1 rounded text-sm"
            >
              Take Control
            </button>
          </div>
        </div>
      )}

      {/* Debug Controls (remove in production) */}
      {process.env.NODE_ENV === 'development' && (
        <div className="absolute bottom-2 right-2 bg-red-800 bg-opacity-75 rounded-lg p-2 text-white text-xs">
          <div className="font-semibold mb-1">Debug Controls:</div>
          <button 
            className="bg-blue-600 hover:bg-blue-700 px-2 py-1 rounded text-xs mr-1"
            onClick={() => {
              console.log('🐛 DEBUG: Force regain control');
              regainControl();
            }}
          >
            Force Regain
          </button>
          <button 
            className="bg-orange-600 hover:bg-orange-700 px-2 py-1 rounded text-xs mr-1"
            onClick={() => {
              console.log('🐛 DEBUG: Force release control');
              releaseControl();
            }}
          >
            Force Release
          </button>
          <button 
            className="bg-gray-600 hover:bg-gray-700 px-2 py-1 rounded text-xs"
            onClick={() => {
              console.log('🐛 DEBUG: Current state:', {
                connected,
                hasControl,
                connecting,
                rfbConnected: rfbRef.current?._rfb_connection_state === 'connected'
              });
            }}
          >
            Log State
          </button>
        </div>
      )}

      {/* Info Overlay for Disconnected State */}
      {!connected && !connecting && !error && (
        <div className="absolute inset-0 flex items-center justify-center bg-black bg-opacity-50 text-white">
          <div className="text-center">
            <div className="text-lg font-semibold mb-2">QEMU Instance</div>
            <div className="text-sm text-gray-300">{instanceId}</div>
            <div className="text-xs text-gray-400 mt-2">Click to connect</div>
          </div>
        </div>
      )}
    </div>
  );
}
