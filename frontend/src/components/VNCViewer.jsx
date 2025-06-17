import React, { useEffect, useRef, useState } from 'react';

/**
 * Simple VNC viewer component that connects to VNC server via WebSocket proxy
 * This implementation creates a basic VNC client without external dependencies
 */
export default function VNCViewer({ instanceId }) {
  const canvasRef = useRef(null);
  const wsRef = useRef(null);
  const [connected, setConnected] = useState(false);
  const [connecting, setConnecting] = useState(false);
  const [error, setError] = useState(null);
  const [framebufferSize, setFramebufferSize] = useState(null);
  const [hasControl, setHasControl] = useState(false);
  
  // Buffer for accumulating partial VNC messages
  const messageBufferRef = useRef(new Uint8Array(0));
  const updateRequestedRef = useRef(false);
  
  // Control release tracking
  const keySequenceRef = useRef([]);
  const lastKeyTimeRef = useRef(0);

  // Debug logging for hasControl state changes
  useEffect(() => {
    console.log(`🎮 hasControl state changed to: ${hasControl} for instance ${instanceId}`);
  }, [hasControl, instanceId]);

  console.log('VNCViewer component mounted for instance:', instanceId);

  useEffect(() => {
    console.log('VNCViewer useEffect triggered for instance:', instanceId);
    if (!instanceId || !canvasRef.current) {
      console.log('Missing instanceId or canvas ref:', { instanceId, canvas: !!canvasRef.current });
      return;
    }

    setConnecting(true);
    setConnected(false);
    setError(null);
    
    // Reset refs for new connection
    messageBufferRef.current = new Uint8Array(0);
    updateRequestedRef.current = false;

    const canvas = canvasRef.current;
    const ctx = canvas.getContext('2d');
    
    // Clear canvas and show connecting message
    ctx.fillStyle = '#000';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = '#fff';
    ctx.font = '16px Arial';
    ctx.textAlign = 'center';
    ctx.fillText('Connecting to VNC...', canvas.width / 2, canvas.height / 2);

    // Create WebSocket connection URL
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const vncUrl = `${protocol}//${window.location.host}/proxy/vnc/${instanceId}/`;
    
    console.log('Connecting to VNC URL:', vncUrl);

    try {
      // Create WebSocket connection to VNC proxy
      const ws = new WebSocket(vncUrl);
      ws.binaryType = 'arraybuffer'; // Important: Handle binary data properly
      wsRef.current = ws;

      // VNC protocol state
      let handshakeStep = 0;
      let serverWidth = 0;
      let serverHeight = 0;
      let pixelFormat = null;

      ws.onopen = () => {
        console.log('VNC WebSocket connected to', instanceId);
        // Don't set connected=true yet, wait for handshake completion
      };

      ws.onmessage = (event) => {
        const data = new Uint8Array(event.data);
        console.log(`VNC message received (step ${handshakeStep}): ${data.length} bytes`);

        // For handshake steps, process immediately
        if (handshakeStep < 4) {
          processHandshakeMessage(data, ws, handshakeStep);
        } else {
          // For framebuffer data, accumulate in buffer to handle partial messages
          accumulateAndProcessVNCData(data, ctx, serverWidth, serverHeight);
        }
      };

      // Helper function to handle handshake steps
      const processHandshakeMessage = (data, ws, currentStep) => {
        if (currentStep === 0) {
          // Step 1: Receive VNC server version (12 bytes: "RFB 003.008\n")
          if (data.length >= 12) {
            const serverVersion = new TextDecoder().decode(data.slice(0, 12));
            console.log('VNC Server version:', JSON.stringify(serverVersion));
            
            // Send back client version (RFB 003.008)
            const clientVersion = 'RFB 003.008\n';
            console.log('Sending client version');
            ws.send(new TextEncoder().encode(clientVersion));
            handshakeStep = 1;
          }
        } else if (currentStep === 1) {
          // Step 2: Receive security types
          if (data.length >= 1) {
            const numSecurityTypes = data[0];
            console.log('Security types available:', numSecurityTypes);
            
            if (numSecurityTypes > 0 && data.length >= 1 + numSecurityTypes) {
              // Look for "None" security type (value 1)
              let hasNoneSecurity = false;
              for (let i = 0; i < numSecurityTypes; i++) {
                if (data[1 + i] === 1) {
                  hasNoneSecurity = true;
                  break;
                }
              }
              
              if (hasNoneSecurity) {
                console.log('Selecting None security (type 1)');
                ws.send(new Uint8Array([1]));
                handshakeStep = 2;
              } else {
                console.error('VNC server requires authentication');
                setError('VNC server requires authentication');
                return;
              }
            }
          }
        } else if (currentStep === 2) {
          // Step 3: Security result (4 bytes)
          if (data.length >= 4) {
            const view = new DataView(data.buffer);
            const result = view.getUint32(0, false); // Big-endian
            console.log('Security result:', result);
            
            if (result === 0) {
              console.log('VNC security handshake successful');
              console.log('Sending ClientInit (shared=1)');
              ws.send(new Uint8Array([1]));
              handshakeStep = 3;
            } else {
              console.error('VNC security handshake failed');
              setError('VNC security handshake failed');
              return;
            }
          }
        } else if (currentStep === 3) {
          // Step 4: ServerInit message
          if (data.length >= 24) {
            const view = new DataView(data.buffer);
            serverWidth = view.getUint16(0, false);
            serverHeight = view.getUint16(2, false);
            console.log(`VNC Server framebuffer: ${serverWidth}x${serverHeight}`);
            
            // Parse pixel format
            pixelFormat = {
              bitsPerPixel: view.getUint8(4),
              depth: view.getUint8(5),
              bigEndian: view.getUint8(6),
              trueColor: view.getUint8(7),
              redMax: view.getUint16(8, false),
              greenMax: view.getUint16(10, false),
              blueMax: view.getUint16(12, false),
              redShift: view.getUint8(14),
              greenShift: view.getUint8(15),
              blueShift: view.getUint8(16)
            };
            
            console.log('Pixel format:', pixelFormat);
            
            // Parse desktop name
            const nameLength = view.getUint32(20, false);
            const desktopName = new TextDecoder().decode(data.slice(24, 24 + nameLength));
            console.log(`Desktop name: "${desktopName}"`);
            
            // Update canvas size to match server framebuffer
            try {
              canvas.width = serverWidth;
              canvas.height = serverHeight;
              setFramebufferSize({ width: serverWidth, height: serverHeight });
              
              // Mark as connected now that handshake is complete
              console.log('🔥 Setting VNC connection states: connected=true, connecting=false, hasControl=true');
              setConnected(true);
              setConnecting(false);
              setHasControl(true); // Gain control when connection is established
              console.log('🔥 VNC states set, should now have control!');
              
              // Draw initial connection screen
              drawConnectedScreen(ctx, serverWidth, serverHeight, instanceId, desktopName);
              
              handshakeStep = 4;
              
              // Request initial framebuffer update with proper throttling
              setTimeout(() => {
                if (!updateRequestedRef.current && wsRef.current && wsRef.current.readyState === WebSocket.OPEN) {
                  console.log('Requesting initial framebuffer update...');
                  requestFramebufferUpdate(ws, 0, 0, serverWidth, serverHeight, false);
                  updateRequestedRef.current = true;
                  
                  // Reset the flag after a delay to allow next update
                  setTimeout(() => {
                    updateRequestedRef.current = false;
                  }, 2000);
                }
              }, 1000);
            } catch (canvasError) {
              console.error('Error setting up canvas:', canvasError);
              setError('Failed to initialize display');
              return;
            }
          }
        }
      };

      // Helper function to accumulate and process VNC data
      const accumulateAndProcessVNCData = (newData, ctx, screenWidth, screenHeight) => {
        // Append new data to buffer
        const currentBuffer = messageBufferRef.current;
        const combinedBuffer = new Uint8Array(currentBuffer.length + newData.length);
        combinedBuffer.set(currentBuffer, 0);
        combinedBuffer.set(newData, currentBuffer.length);
        messageBufferRef.current = combinedBuffer;
        
        console.log(`Accumulated buffer size: ${combinedBuffer.length} bytes`);
        
        // Safety check: if buffer grows too large, reset it to prevent memory issues
        if (combinedBuffer.length > 10 * 1024 * 1024) { // 10MB limit
          console.warn('VNC buffer too large, resetting');
          messageBufferRef.current = new Uint8Array(0);
          return;
        }
        
        // Try to process complete messages from buffer
        let processed = 0;
        while (processed < combinedBuffer.length) {
          const remaining = combinedBuffer.slice(processed);
          const messageLength = tryProcessCompleteVNCMessage(remaining, ctx, screenWidth, screenHeight);
          
          if (messageLength > 0) {
            processed += messageLength;
            console.log(`Processed ${messageLength} bytes, ${processed}/${combinedBuffer.length} total`);
          } else {
            // Not enough data for a complete message, wait for more
            console.log(`Incomplete message, waiting for more data. Have ${remaining.length} bytes`);
            break;
          }
        }
        
        // Keep unprocessed data in buffer
        if (processed > 0) {
          messageBufferRef.current = combinedBuffer.slice(processed);
          console.log(`Remaining buffer size: ${messageBufferRef.current.length} bytes`);
        }
      };

      ws.onerror = (err) => {
        console.error('VNC WebSocket error:', err);
        setError('Failed to connect to VNC server');
        setConnecting(false);
        setConnected(false);
      };

      ws.onclose = (e) => {
        console.log('VNC WebSocket closed:', e.code, e.reason);
        setConnected(false);
        setConnecting(false);
        setHasControl(false); // Lose control when connection is lost
        if (e.code !== 1000) {
          setError('Connection lost');
        }
      };

    } catch (err) {
      console.error('Failed to create VNC WebSocket:', err);
      setError(`Connection failed: ${err.message}`);
      setConnecting(false);
    }

    // Cleanup function
    return () => {
      if (wsRef.current) {
        wsRef.current.close();
        wsRef.current = null;
      }
      // Reset refs and state
      messageBufferRef.current = new Uint8Array(0);
      updateRequestedRef.current = false;
      keySequenceRef.current = [];
      lastKeyTimeRef.current = 0;
      setConnected(false);
      setConnecting(false);
      setHasControl(false);
    };
  }, [instanceId]);

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
      if (event.detail.instanceId === instanceId && hasControl && connected) {
        const { x, y, button, pressed } = event.detail;
        console.log(`🎮 VR pointer: (${x}, ${y}) button=${button} pressed=${pressed}`);
        
        if (x >= 0 && y >= 0 && wsRef.current && wsRef.current.readyState === WebSocket.OPEN) {
          const buttonMask = pressed ? (1 << button) : 0;
          sendPointerEvent(x, y, buttonMask);
        }
      }
    };

    const handleVRKeyboard = (event) => {
      if (event.detail.instanceId === instanceId && hasControl && connected) {
        const { key, pressed } = event.detail;
        console.log(`🎮 VR keyboard: key=${key} pressed=${pressed}`);
        
        // Convert VR key to keySym (basic implementation)
        const keySym = getKeySymbol({ key, code: key });
        if (keySym > 0) {
          sendKeyEvent(keySym, pressed);
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

  // Helper function to request framebuffer updates
  const requestFramebufferUpdate = (ws, x, y, width, height, incremental = false) => {
    if (!ws || ws.readyState !== WebSocket.OPEN) return;
    
    const buffer = new ArrayBuffer(10);
    const view = new DataView(buffer);
    view.setUint8(0, 3); // FramebufferUpdateRequest message type
    view.setUint8(1, incremental ? 1 : 0); // incremental flag
    view.setUint16(2, x, false); // x position (big-endian)
    view.setUint16(4, y, false); // y position (big-endian)
    view.setUint16(6, width, false); // width (big-endian)
    view.setUint16(8, height, false); // height (big-endian)
    ws.send(buffer);
    console.log(`Requested framebuffer update: ${x},${y} ${width}x${height} incremental=${incremental}`);
  };

  // Helper function to send pointer (mouse) events
  const sendPointerEvent = (x, y, buttonMask) => {
    if (!wsRef.current || wsRef.current.readyState !== WebSocket.OPEN) {
      console.warn('Cannot send pointer event: VNC not connected');
      return;
    }
    
    try {
      const buffer = new ArrayBuffer(6);
      const view = new DataView(buffer);
      view.setUint8(0, 5); // PointerEvent message type
      view.setUint8(1, buttonMask); // button mask (1 = left, 2 = middle, 4 = right)
      view.setUint16(2, x, false); // x position (big-endian)
      view.setUint16(4, y, false); // y position (big-endian)
      
      wsRef.current.send(buffer);
      console.log(`Sent pointer event: (${x}, ${y}) buttons=${buttonMask}`);
    } catch (error) {
      console.error('Error sending pointer event:', error);
    }
  };

  // Helper function to send keyboard events
  const sendKeyEvent = (keySym, down) => {
    if (!wsRef.current || wsRef.current.readyState !== WebSocket.OPEN) {
      console.warn('Cannot send key event: VNC not connected');
      return;
    }
    
    try {
      const buffer = new ArrayBuffer(8);
      const view = new DataView(buffer);
      view.setUint8(0, 4); // KeyEvent message type
      view.setUint8(1, down ? 1 : 0); // down flag
      view.setUint16(2, 0, false); // padding
      view.setUint32(4, keySym, false); // key symbol (big-endian)
      
      wsRef.current.send(buffer);
      console.log(`Sent key event: keySym=${keySym} (0x${keySym.toString(16)}) ${down ? 'down' : 'up'}`);
    } catch (error) {
      console.error('Error sending key event:', error);
    }
  };

  // Comprehensive key mapping for full keyboard support
  const getKeySymbol = (event) => {
    const key = event.key;
    const code = event.code;
    
    console.log(`Key pressed: key="${key}", code="${code}", ctrl=${event.ctrlKey}, alt=${event.altKey}, shift=${event.shiftKey}`);
    
    // Handle printable characters
    if (key.length === 1) {
      const charCode = key.charCodeAt(0);
      
      // Handle special character mappings
      if (event.shiftKey) {
        const shiftMap = {
          '`': 0x007e, // ~
          '1': 0x0021, // !
          '2': 0x0040, // @
          '3': 0x0023, // #
          '4': 0x0024, // $
          '5': 0x0025, // %
          '6': 0x005e, // ^
          '7': 0x0026, // &
          '8': 0x002a, // *
          '9': 0x0028, // (
          '0': 0x0029, // )
          '-': 0x005f, // _
          '=': 0x002b, // +
          '[': 0x007b, // {
          ']': 0x007d, // }
          '\\': 0x007c, // |
          ';': 0x003a, // :
          "'": 0x0022, // "
          ',': 0x003c, // <
          '.': 0x003e, // >
          '/': 0x003f  // ?
        };
        
        if (shiftMap[key]) {
          return shiftMap[key];
        }
      }
      
      return charCode;
    }
    
    // Handle special keys with comprehensive mapping
    const specialKeys = {
      // Navigation keys
      'ArrowUp': 0xff52,
      'ArrowDown': 0xff54,
      'ArrowLeft': 0xff51,
      'ArrowRight': 0xff53,
      'Home': 0xff50,
      'End': 0xff57,
      'PageUp': 0xff55,
      'PageDown': 0xff56,
      
      // Function keys
      'F1': 0xffbe, 'F2': 0xffbf, 'F3': 0xffc0, 'F4': 0xffc1,
      'F5': 0xffc2, 'F6': 0xffc3, 'F7': 0xffc4, 'F8': 0xffc5,
      'F9': 0xffc6, 'F10': 0xffc7, 'F11': 0xffc8, 'F12': 0xffc9,
      
      // Editing keys
      'Enter': 0xff0d,
      'Return': 0xff0d,
      'Backspace': 0xff08,
      'Delete': 0xffff,
      'Insert': 0xff63,
      'Tab': 0xff09,
      'Escape': 0xff1b,
      'Space': 0x0020,
      
      // Modifier keys
      'Shift': 0xffe1,
      'ShiftLeft': 0xffe1,
      'ShiftRight': 0xffe2,
      'Control': 0xffe3,
      'ControlLeft': 0xffe3,
      'ControlRight': 0xffe4,
      'Alt': 0xffe9,
      'AltLeft': 0xffe9,
      'AltRight': 0xffea,
      'Meta': 0xffeb,
      'MetaLeft': 0xffeb,
      'MetaRight': 0xffec,
      'ContextMenu': 0xff67,
      
      // Lock keys
      'CapsLock': 0xffe5,
      'NumLock': 0xff7f,
      'ScrollLock': 0xff14,
      
      // Numeric keypad
      'Numpad0': 0xffb0, 'Numpad1': 0xffb1, 'Numpad2': 0xffb2,
      'Numpad3': 0xffb3, 'Numpad4': 0xffb4, 'Numpad5': 0xffb5,
      'Numpad6': 0xffb6, 'Numpad7': 0xffb7, 'Numpad8': 0xffb8,
      'Numpad9': 0xffb9, 'NumpadDecimal': 0xffae, 'NumpadDivide': 0xffaf,
      'NumpadMultiply': 0xffaa, 'NumpadSubtract': 0xffad, 'NumpadAdd': 0xffab,
      'NumpadEnter': 0xff8d, 'NumpadEqual': 0xffbd,
      
      // Media keys
      'AudioVolumeUp': 0x1008ff13,
      'AudioVolumeDown': 0x1008ff11,
      'AudioVolumeMute': 0x1008ff12,
      'MediaPlayPause': 0x1008ff14,
      'MediaStop': 0x1008ff15,
      'MediaTrackNext': 0x1008ff17,
      'MediaTrackPrevious': 0x1008ff16,
      
      // System keys
      'PrintScreen': 0xff61,
      'Pause': 0xff13,
      'Break': 0xff6b
    };
    
    // Try key name first, then code
    return specialKeys[key] || specialKeys[code] || 0;
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
    
    // Control release sequences (multiple options for accessibility)
    const releaseSequences = [
      // Primary sequence: Ctrl+Alt+R (Release)
      ['Control', 'Alt', 'KeyR'],
      // Alternative: Ctrl+Shift+Escape (Task manager style)
      ['Control', 'Shift', 'Escape'],
      // VR-friendly: F10 three times quickly
      ['F10', 'F10', 'F10'],
      // Gaming-friendly: Ctrl+Alt+Q (Quit control)
      ['Control', 'Alt', 'KeyQ']
    ];
    
    // Add current key to sequence
    keySequenceRef.current.push(event.code);
    
    // Keep only last 5 keys to prevent memory issues
    if (keySequenceRef.current.length > 5) {
      keySequenceRef.current = keySequenceRef.current.slice(-5);
    }
    
    // Check if any release sequence is matched
    for (const sequence of releaseSequences) {
      if (keySequenceRef.current.length >= sequence.length) {
        const lastKeys = keySequenceRef.current.slice(-sequence.length);
        
        // Special handling for F10 triple-tap (time-sensitive)
        if (sequence.every(key => key === 'F10')) {
          const f10Times = keySequenceRef.current.filter(key => key === 'F10');
          if (f10Times.length >= 3) {
            // Check if the last 3 F10 presses were within 2 seconds
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
    console.log('🔓 Releasing control of VNC instance:', instanceId);
    setHasControl(false);
    keySequenceRef.current = [];
    
    // Send a visual indication
    const canvas = canvasRef.current;
    if (canvas) {
      const ctx = canvas.getContext('2d');
      
      // Draw release notification overlay
      ctx.save();
      ctx.fillStyle = 'rgba(255, 165, 0, 0.8)';
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      
      ctx.fillStyle = '#fff';
      ctx.font = 'bold 24px Arial';
      ctx.textAlign = 'center';
      ctx.fillText('🔓 CONTROL RELEASED', canvas.width / 2, canvas.height / 2 - 20);
      
      ctx.font = '16px Arial';
      ctx.fillText('Click to regain control', canvas.width / 2, canvas.height / 2 + 20);
      
      ctx.font = '12px Arial';
      ctx.fillText('VR users: Use trigger button to regain control', canvas.width / 2, canvas.height / 2 + 50);
      ctx.restore();
      
      // Clear the overlay after 2 seconds
      setTimeout(() => {
        if (!hasControl) {
          // Redraw the last framebuffer state
          requestFramebufferUpdate(wsRef.current, 0, 0, canvas.width, canvas.height, false);
        }
      }, 2000);
    }
    
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
    
    console.log('🔒 Regaining control of VNC instance:', instanceId);
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
    
    // Focus the canvas for keyboard input
    const canvas = canvasRef.current;
    if (canvas) {
      canvas.focus();
      console.log('🎯 Canvas focused for keyboard input');
    }
    
    console.log('🎮 Control regain event dispatched for VR/external controllers');
    console.log(`✅ Control regained successfully: hasControl will be=${true}`);
  };

  // Enhanced keyboard handler with full support
  const handleKeyDown = (event) => {
    if (!connected) {
      console.log('Key event ignored: VNC not connected');
      return;
    }
    
    // Check for control release sequence first
    if (hasControl && checkControlReleaseSequence(event)) {
      console.log('🔓 Control release sequence detected!');
      releaseControl();
      event.preventDefault();
      event.stopPropagation();
      return;
    }
    
    // If we don't have control, ignore input (except for regaining control)
    if (!hasControl) {
      console.log('Key event ignored: No control of this instance');
      return;
    }
    
    // Prevent browser shortcuts from interfering
    event.preventDefault();
    event.stopPropagation();
    
    try {
      const keySym = getKeySymbol(event);
      
      if (keySym === 0) {
        console.warn(`Unknown key: "${event.key}" (code: "${event.code}")`);
        return;
      }
      
      console.log(`Sending key down: "${event.key}" -> keySym=${keySym} (0x${keySym.toString(16)})`);
      sendKeyEvent(keySym, true);
      
      // Store the key for key up event
      event.target.dataset.lastKeySym = keySym;
      
    } catch (error) {
      console.error('Error handling key down event:', error);
    }
  };
  
  const handleKeyUp = (event) => {
    if (!connected || !hasControl) return;
    
    event.preventDefault();
    event.stopPropagation();
    
    try {
      // Use stored keySym from keydown or calculate again
      let keySym = parseInt(event.target.dataset.lastKeySym);
      if (!keySym || isNaN(keySym)) {
        keySym = getKeySymbol(event);
      }
      
      if (keySym === 0) {
        console.warn(`Unknown key up: "${event.key}" (code: "${event.code}")`);
        return;
      }
      
      console.log(`Sending key up: "${event.key}" -> keySym=${keySym} (0x${keySym.toString(16)})`);
      sendKeyEvent(keySym, false);
      
      // Clear stored keySym
      delete event.target.dataset.lastKeySym;
      
    } catch (error) {
      console.error('Error handling key up event:', error);
    }
  };

  // Helper function to try processing a complete VNC message
  const tryProcessCompleteVNCMessage = (data, ctx, screenWidth, screenHeight) => {
    if (data.length < 4) return 0; // Need at least message header
    
    const view = new DataView(data.buffer, data.byteOffset);
    const messageType = view.getUint8(0);
    
    console.log(`Trying to process VNC message type: ${messageType}, available data: ${data.length} bytes`);
    
    if (messageType === 0) {
      // FramebufferUpdate message
      return tryProcessFramebufferUpdate(data, ctx, screenWidth, screenHeight);
    } else {
      console.log(`Unhandled VNC message type: ${messageType}`);
      // For unknown message types, we don't know the length, so consume what we have
      return data.length;
    }
  };

  // Helper function to try processing a complete framebuffer update
  const tryProcessFramebufferUpdate = (data, ctx, screenWidth, screenHeight) => {
    try {
      if (data.length < 4) return 0; // Need at least header
      
      const view = new DataView(data.buffer, data.byteOffset);
      const numRectangles = view.getUint16(2, false); // big-endian
      console.log(`Framebuffer update with ${numRectangles} rectangles`);
      
      let offset = 4; // Start after header
      let processedRectangles = 0;
      
      for (let i = 0; i < numRectangles; i++) {
        if (offset + 12 > data.length) {
          console.log(`Not enough data for rectangle header ${i}: need ${offset + 12}, have ${data.length}`);
          return 0; // Not enough data for rectangle header
        }
        
        const x = view.getUint16(offset, false);
        const y = view.getUint16(offset + 2, false);
        const width = view.getUint16(offset + 4, false);
        const height = view.getUint16(offset + 6, false);
        const encoding = view.getInt32(offset + 8, false);
        
        console.log(`Rectangle ${i}: x=${x}, y=${y}, ${width}x${height}, encoding=${encoding}`);
        
        offset += 12; // Move past rectangle header
        
        if (encoding === 0) {
          // Raw encoding - 4 bytes per pixel (32-bit BGRA)
          const pixelDataLength = width * height * 4;
          
          if (offset + pixelDataLength > data.length) {
            console.log(`Not enough data for raw pixels: need ${pixelDataLength}, have ${data.length - offset}`);
            return 0; // Not enough data for pixel data
          }
          
          console.log(`Drawing raw pixels: ${pixelDataLength} bytes`);
          drawRawPixels(ctx, data.slice(offset, offset + pixelDataLength), x, y, width, height);
          offset += pixelDataLength;
          processedRectangles++;
        } else {
          console.log(`Unsupported encoding: ${encoding}`);
          // For unsupported encodings, we don't know the data size, so stop processing
          break;
        }
      }
      
      // Draw update indicator
      if (processedRectangles > 0) {
        ctx.fillStyle = '#00ff00';
        ctx.fillRect(screenWidth - 10, screenHeight - 10, 8, 8);
        
        // Request next update with conservative throttling to avoid overwhelming the connection
        if (!updateRequestedRef.current && wsRef.current && wsRef.current.readyState === WebSocket.OPEN) {
          updateRequestedRef.current = true;
          setTimeout(() => {
            if (wsRef.current && wsRef.current.readyState === WebSocket.OPEN) {
              requestFramebufferUpdate(wsRef.current, 0, 0, screenWidth, screenHeight, true);
            }
            updateRequestedRef.current = false;
          }, 2000); // 2 second throttling to be conservative
        }
      }
      
      return offset; // Return bytes consumed
      
    } catch (error) {
      console.error('Error processing framebuffer update:', error);
      return 0;
    }
  };

  // Helper function to draw raw pixel data
  const drawRawPixels = (ctx, pixelData, x, y, width, height) => {
    try {
      const imageData = ctx.createImageData(width, height);
      const pixels = imageData.data;
      
      // Convert VNC pixel format to canvas RGBA
      for (let i = 0; i < width * height; i++) {
        const srcOffset = i * 4;
        const dstOffset = i * 4;
        
        // VNC uses BGRA or RGBA - assume BGRA for now
        pixels[dstOffset + 0] = pixelData[srcOffset + 2]; // R
        pixels[dstOffset + 1] = pixelData[srcOffset + 1]; // G
        pixels[dstOffset + 2] = pixelData[srcOffset + 0]; // B
        pixels[dstOffset + 3] = 255; // A (fully opaque)
      }
      
      ctx.putImageData(imageData, x, y);
    } catch (error) {
      console.error('Error drawing raw pixels:', error);
      
      // Fallback: draw a solid rectangle
      ctx.fillStyle = '#444444';
      ctx.fillRect(x, y, width, height);
    }
  };

  // Enhanced mouse event handlers with full button support
  const handleCanvasClick = (event) => {
    console.log(`🖱️ Canvas click detected: connected=${connected}, hasControl=${hasControl}, wsState=${wsRef.current?.readyState}`);
    console.log(`🖱️ WebSocket OPEN constant=${WebSocket.OPEN}, current readyState=${wsRef.current?.readyState}`);
    console.log(`🖱️ wsRef.current exists: ${!!wsRef.current}`);
    
    if (!connected || !wsRef.current || wsRef.current.readyState !== WebSocket.OPEN) {
      console.log(`🖱️ Click blocked - connected: ${connected}, wsRef: ${!!wsRef.current}, readyState: ${wsRef.current?.readyState}`);
      if (!connected) {
        console.log('Mouse click ignored: VNC not connected, attempting reconnection');
        handleReconnect();
      }
      return;
    }
    
    // If we don't have control, regain it
    if (!hasControl) {
      console.log('🔒 Regaining control via click');
      regainControl();
      return;
    }
    
    console.log('🖱️ Processing normal click (already have control)');
    
    event.preventDefault();
    
    try {
      const canvas = canvasRef.current;
      const rect = canvas.getBoundingClientRect();
      const scaleX = canvas.width / rect.width;
      const scaleY = canvas.height / rect.height;
      
      const x = Math.floor((event.clientX - rect.left) * scaleX);
      const y = Math.floor((event.clientY - rect.top) * scaleY);
      
      // Validate coordinates
      if (x < 0 || y < 0 || x >= canvas.width || y >= canvas.height) {
        console.warn(`Mouse click outside canvas bounds: (${x}, ${y}), canvas: ${canvas.width}x${canvas.height}`);
        return;
      }
      
      // Determine button mask
      let buttonMask = 0;
      if (event.button === 0) buttonMask = 1; // Left button
      else if (event.button === 1) buttonMask = 2; // Middle button  
      else if (event.button === 2) buttonMask = 4; // Right button
      
      console.log(`VNC Click at: (${x}, ${y}) button=${event.button} mask=${buttonMask}`);
      
      // Send button down and up events
      sendPointerEvent(x, y, buttonMask);
      setTimeout(() => {
        sendPointerEvent(x, y, 0); // Button up
      }, 50);
      
      // Focus the canvas for keyboard events
      canvas.focus();
      
    } catch (error) {
      console.error('Error handling mouse click:', error);
    }
  };
  
  const handleCanvasMouseDown = (event) => {
    if (!connected || !wsRef.current || wsRef.current.readyState !== WebSocket.OPEN) return;
    if (!hasControl) return; // Ignore if no control
    
    event.preventDefault();
    
    try {
      const canvas = canvasRef.current;
      const rect = canvas.getBoundingClientRect();
      const scaleX = canvas.width / rect.width;
      const scaleY = canvas.height / rect.height;
      
      const x = Math.floor((event.clientX - rect.left) * scaleX);
      const y = Math.floor((event.clientY - rect.top) * scaleY);
      
      let buttonMask = 0;
      if (event.button === 0) buttonMask = 1; // Left button
      else if (event.button === 1) buttonMask = 2; // Middle button
      else if (event.button === 2) buttonMask = 4; // Right button
      
      console.log(`VNC Mouse down at: (${x}, ${y}) button=${event.button} mask=${buttonMask}`);
      sendPointerEvent(x, y, buttonMask);
      
      // Store button state for mouse up
      canvas.dataset.mouseButton = buttonMask;
      canvas.dataset.mouseX = x;
      canvas.dataset.mouseY = y;
      
    } catch (error) {
      console.error('Error handling mouse down:', error);
    }
  };
  
  const handleCanvasMouseUp = (event) => {
    if (!connected || !wsRef.current || wsRef.current.readyState !== WebSocket.OPEN) return;
    if (!hasControl) return; // Ignore if no control
    
    event.preventDefault();
    
    try {
      const canvas = canvasRef.current;
      const rect = canvas.getBoundingClientRect();
      const scaleX = canvas.width / rect.width;
      const scaleY = canvas.height / rect.height;
      
      const x = Math.floor((event.clientX - rect.left) * scaleX);
      const y = Math.floor((event.clientY - rect.top) * scaleY);
      
      console.log(`VNC Mouse up at: (${x}, ${y}) button=${event.button}`);
      sendPointerEvent(x, y, 0); // All buttons up
      
      // Clear stored button state
      delete canvas.dataset.mouseButton;
      delete canvas.dataset.mouseX;
      delete canvas.dataset.mouseY;
      
    } catch (error) {
      console.error('Error handling mouse up:', error);
    }
  };
  
  const handleCanvasMouseMove = (event) => {
    if (!connected || !wsRef.current || wsRef.current.readyState !== WebSocket.OPEN) return;
    if (!hasControl) return; // Ignore if no control
    
    try {
      const canvas = canvasRef.current;
      const rect = canvas.getBoundingClientRect();
      const scaleX = canvas.width / rect.width;
      const scaleY = canvas.height / rect.height;
      
      const x = Math.floor((event.clientX - rect.left) * scaleX);
      const y = Math.floor((event.clientY - rect.top) * scaleY);
      
      // Only send if mouse is being dragged (button down)
      const buttonMask = parseInt(canvas.dataset.mouseButton) || 0;
      
      if (buttonMask > 0) {
        console.log(`VNC Mouse drag to: (${x}, ${y}) mask=${buttonMask}`);
        sendPointerEvent(x, y, buttonMask);
        canvas.dataset.mouseX = x;
        canvas.dataset.mouseY = y;
      }
      
    } catch (error) {
      console.error('Error handling mouse move:', error);
    }
  };
  
  const handleContextMenu = (event) => {
    // Prevent browser context menu to allow right-click to reach VNC
    event.preventDefault();
  };

  const handleReconnect = () => {
    console.log('🔄 handleReconnect called - resetting state and triggering reconnection');
    setError(null);
    setConnecting(false);
    setConnected(false);
    setHasControl(false); // Reset control state
    // Reset refs for new connection
    messageBufferRef.current = new Uint8Array(0);
    updateRequestedRef.current = false;
    keySequenceRef.current = [];
    lastKeyTimeRef.current = 0;
    
    // Close existing WebSocket if any
    if (wsRef.current) {
      wsRef.current.close();
      wsRef.current = null;
    }
    
    // Clear canvas
    const canvas = canvasRef.current;
    if (canvas) {
      const ctx = canvas.getContext('2d');
      ctx.fillStyle = '#000';
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      ctx.fillStyle = '#fff';
      ctx.font = '16px Arial';
      ctx.textAlign = 'center';
      ctx.fillText('Reconnecting...', canvas.width / 2, canvas.height / 2);
    }
    
    // Force a re-render by updating a state that will trigger the useEffect
    // We'll use a timestamp to ensure the effect runs
    setConnecting(true);
    console.log('🔄 Reconnection state reset complete, useEffect should trigger');
  };

  // Helper function to draw connected screen
  function drawConnectedScreen(ctx, width, height, instanceId, desktopName = '') {
    // Draw a test pattern to show connection is working
    ctx.fillStyle = '#1a1a2e';
    ctx.fillRect(0, 0, width, height);
    
    // Draw QEMU screen simulation
    ctx.fillStyle = '#0f4c75';
    ctx.fillRect(50, 50, width - 100, height - 100);
    
    ctx.fillStyle = '#16537e';
    ctx.fillRect(60, 60, width - 120, 40);
    
    ctx.fillStyle = '#fff';
    ctx.font = 'bold 16px monospace';
    ctx.textAlign = 'left';
    ctx.fillText('QEMU Emulator', 70, 85);
    
    ctx.font = '14px monospace';
    ctx.fillText(`Instance: ${instanceId}`, 70, 120);
    ctx.fillText('Status: VNC Connected', 70, 140);
    ctx.fillText(`Resolution: ${width}x${height}`, 70, 160);
    if (desktopName) {
      ctx.fillText(`Desktop: ${desktopName}`, 70, 180);
    }
    
    // Draw Windows 98 style desktop simulation
    ctx.fillStyle = '#008080';
    ctx.fillRect(60, 180, width - 120, height - 240);
    
    // Taskbar
    ctx.fillStyle = '#c0c0c0';
    ctx.fillRect(60, height - 110, width - 120, 30);
    
    // Start button
    ctx.fillStyle = '#808080';
    ctx.fillRect(65, height - 105, 60, 20);
    ctx.fillStyle = '#000';
    ctx.font = '12px Arial';
    ctx.fillText('Start', 70, height - 92);
    
    ctx.fillStyle = '#fff';
    ctx.font = '12px Arial';
    ctx.textAlign = 'center';
    ctx.fillText('VNC Protocol Connected - Click to interact', width / 2, height - 50);
  }

  return (
    <div className="relative w-full h-full bg-black rounded-lg overflow-hidden">
      {/* VNC Display Canvas */}
      <canvas
        ref={canvasRef}
        width={framebufferSize?.width || 1024}
        height={framebufferSize?.height || 768}
        className="w-full h-full cursor-pointer"
        onClick={handleCanvasClick}
        onMouseDown={handleCanvasMouseDown}
        onMouseUp={handleCanvasMouseUp}
        onMouseMove={handleCanvasMouseMove}
        onContextMenu={handleContextMenu}
        onKeyDown={handleKeyDown}
        onKeyUp={handleKeyUp}
        tabIndex={0}
        style={{ 
          imageRendering: 'pixelated', 
          outline: 'none',
          userSelect: 'none' // Prevent text selection
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
          <div>VNC Connected</div>
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
          <div className="font-semibold mb-1">VNC Controls:</div>
          <div>• All mouse buttons and keyboard keys supported</div>
          <div>• Right-click, function keys, and special keys work</div>
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
                wsState: wsRef.current?.readyState,
                wsOpen: WebSocket.OPEN
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
