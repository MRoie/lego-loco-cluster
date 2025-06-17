import React, { useEffect, useRef, useState } from 'react';
import VNC from 'react-vnc';

/**
 * VR-compatible React-VNC based VNC viewer component
 * Uses the react-vnc library with enhanced VR controller support
 */
export default function VRReactVNCViewer({ instanceId, position = [0, 0, -2], scale = [1, 1, 1] }) {
  const [connected, setConnected] = useState(false);
  const [connecting, setConnecting] = useState(false);
  const [error, setError] = useState(null);
  const [hasControl, setHasControl] = useState(false);
  const vncRef = useRef(null);
  
  // Control release tracking
  const keySequenceRef = useRef([]);
  const lastKeyTimeRef = useRef(0);

  // Debug logging for hasControl state changes
  useEffect(() => {
    console.log(`🎮 VR ReactVNC hasControl state changed to: ${hasControl} for instance ${instanceId}`);
  }, [hasControl, instanceId]);

  console.log('VR ReactVNCViewer component mounted for instance:', instanceId);

  // Create WebSocket connection URL
  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  const vncUrl = `${protocol}//${window.location.host}/proxy/vnc/${instanceId}/`;

  // VNC event handlers
  const handleConnect = () => {
    console.log('VR ReactVNC connected to', instanceId);
    setConnected(true);
    setConnecting(false);
    setHasControl(true);
    setError(null);
  };

  const handleDisconnect = () => {
    console.log('VR ReactVNC disconnected from', instanceId);
    setConnected(false);
    setConnecting(false);
    setHasControl(false);
  };

  const handleError = (error) => {
    console.error('VR ReactVNC error:', error);
    setError(`Connection failed: ${error.message || error}`);
    setConnecting(false);
    setConnected(false);
  };

  // Enhanced VR Controller Support
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

    // Enhanced VR input events with better coordinate mapping
    const handleVRPointer = (event) => {
      if (event.detail.instanceId === instanceId && hasControl && connected && vncRef.current) {
        const { x, y, button, pressed } = event.detail;
        console.log(`🎮 VR pointer: (${x}, ${y}) button=${button} pressed=${pressed}`);
        
        // Enhanced coordinate mapping for VR context
        const canvas = vncRef.current.querySelector('canvas');
        if (canvas && x >= 0 && y >= 0) {
          const rect = canvas.getBoundingClientRect();
          
          // Map VR coordinates to canvas coordinates
          const canvasX = Math.min(Math.max(x * rect.width, 0), rect.width);
          const canvasY = Math.min(Math.max(y * rect.height, 0), rect.height);
          
          const clientX = rect.left + canvasX;
          const clientY = rect.top + canvasY;
          
          // Dispatch both mouse events and pointer events for better compatibility
          const eventType = pressed ? 'mousedown' : 'mouseup';
          const mouseEvent = new MouseEvent(eventType, {
            clientX,
            clientY,
            button,
            buttons: pressed ? (1 << button) : 0,
            bubbles: true,
            cancelable: true
          });
          
          // Also dispatch a mousemove event to update cursor position
          const moveEvent = new MouseEvent('mousemove', {
            clientX,
            clientY,
            bubbles: true,
            cancelable: true
          });
          
          canvas.dispatchEvent(moveEvent);
          canvas.dispatchEvent(mouseEvent);
        }
      }
    };

    const handleVRKeyboard = (event) => {
      if (event.detail.instanceId === instanceId && hasControl && connected && vncRef.current) {
        const { key, pressed } = event.detail;
        console.log(`🎮 VR keyboard: key=${key} pressed=${pressed}`);
        
        // Enhanced keyboard handling for VR
        const canvas = vncRef.current.querySelector('canvas');
        if (canvas) {
          const eventType = pressed ? 'keydown' : 'keyup';
          
          // Map VR key inputs to proper keyboard events
          const keyCode = getKeyCode(key);
          const keyEvent = new KeyboardEvent(eventType, {
            key,
            code: 'Key' + key.toUpperCase(),
            keyCode,
            which: keyCode,
            bubbles: true,
            cancelable: true
          });
          
          // Focus canvas first to ensure events are received
          canvas.focus();
          canvas.dispatchEvent(keyEvent);
        }
      }
    };

    // VR-specific gesture handling
    const handleVRGesture = (event) => {
      if (event.detail.instanceId === instanceId && connected) {
        const { gesture } = event.detail;
        console.log(`🎮 VR gesture: ${gesture}`);
        
        switch (gesture) {
          case 'grab':
            if (!hasControl) regainControl();
            break;
          case 'release':
            if (hasControl) releaseControl();
            break;
          case 'pinch':
            // Could implement zoom functionality
            break;
          default:
            break;
        }
      }
    };

    // Add VR event listeners
    window.addEventListener('vrTriggerPress', handleVRTrigger);
    window.addEventListener('vrReleaseGesture', handleVRRelease);
    window.addEventListener('vrPointerEvent', handleVRPointer);
    window.addEventListener('vrKeyboardEvent', handleVRKeyboard);
    window.addEventListener('vrGestureEvent', handleVRGesture);

    // Cleanup VR event listeners
    return () => {
      window.removeEventListener('vrTriggerPress', handleVRTrigger);
      window.removeEventListener('vrReleaseGesture', handleVRRelease);
      window.removeEventListener('vrPointerEvent', handleVRPointer);
      window.removeEventListener('vrKeyboardEvent', handleVRKeyboard);
      window.removeEventListener('vrGestureEvent', handleVRGesture);
    };
  }, [instanceId, hasControl, connected]);

  // Helper function to get key codes for VR keyboard mapping
  const getKeyCode = (key) => {
    const keyCodes = {
      'Enter': 13,
      'Escape': 27,
      'Space': 32,
      'ArrowLeft': 37,
      'ArrowUp': 38,
      'ArrowRight': 39,
      'ArrowDown': 40,
      'Delete': 46,
      'Backspace': 8,
      'Tab': 9,
      'Shift': 16,
      'Control': 17,
      'Alt': 18,
    };
    
    if (keyCodes[key]) return keyCodes[key];
    if (key.length === 1) return key.toUpperCase().charCodeAt(0);
    return 0;
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
    
    // VR-friendly control release sequences
    const releaseSequences = [
      // VR-primary: F10 three times quickly
      ['F10', 'F10', 'F10'],
      // Traditional: Ctrl+Alt+R
      ['Control', 'Alt', 'KeyR'],
      // Alternative: Ctrl+Shift+Escape
      ['Control', 'Shift', 'Escape'],
      // VR-friendly: Escape three times
      ['Escape', 'Escape', 'Escape']
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
        
        // Special handling for triple-tap sequences
        if (sequence.every((key, index) => key === sequence[0])) {
          const targetKey = sequence[0];
          const targetCount = sequence.length;
          const recentKeys = keySequenceRef.current.filter(key => key === targetKey);
          if (recentKeys.length >= targetCount) {
            return true;
          }
        } else {
          // Check exact sequence match
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
    console.log('🔓 Releasing control of VR ReactVNC instance:', instanceId);
    setHasControl(false);
    keySequenceRef.current = [];
    
    // Dispatch custom event for VR and other controllers
    const releaseEvent = new CustomEvent('vncControlReleased', {
      detail: { 
        instanceId, 
        timestamp: Date.now(),
        reason: 'vr_gesture',
        source: 'vr'
      }
    });
    window.dispatchEvent(releaseEvent);
    
    console.log('🎮 VR Control release event dispatched');
  };

  // Regain control of this instance
  const regainControl = () => {
    console.log(`🔒 VR regainControl called: connected=${connected}, currentControl=${hasControl}`);
    
    if (!connected) {
      console.log('Cannot regain control: VNC not connected');
      return;
    }
    
    console.log('🔒 Regaining control of VR ReactVNC instance:', instanceId);
    setHasControl(true);
    keySequenceRef.current = [];
    
    // Dispatch custom event for VR and other controllers
    const regainEvent = new CustomEvent('vncControlRegained', {
      detail: { 
        instanceId, 
        timestamp: Date.now(),
        method: 'vr_trigger',
        source: 'vr'
      }
    });
    window.dispatchEvent(regainEvent);
    
    console.log('🎮 VR Control regain event dispatched');
  };

  const handleReconnect = () => {
    console.log('VR: Reconnecting to VNC...');
    setError(null);
    setConnecting(true);
    setConnected(false);
    setHasControl(false);
  };

  if (!instanceId) {
    return (
      <a-entity 
        position={position.join(' ')}
        scale={scale.join(' ')}
        geometry="primitive: plane; width: 2; height: 1.5"
        material="color: #333; opacity: 0.8"
        text="value: No instance selected; align: center; color: white; width: 8"
      />
    );
  }

  return (
    <a-entity 
      position={position.join(' ')}
      scale={scale.join(' ')}
      className="vr-vnc-container"
    >
      {/* VNC Display Plane */}
      <a-plane
        ref={vncRef}
        width="2"
        height="1.5"
        material="color: black; opacity: 1"
        cursor-listener=""
        raycaster-target=""
      >
        {/* React VNC Component as HTML entity */}
        <a-entity
          html={`
            <div style="width: 800px; height: 600px; background: black;">
              <div id="vnc-${instanceId}"></div>
            </div>
          `}
          html-shader="fps: 30"
          position="0 0 0.01"
        />
      </a-plane>

      {/* Connection status overlay */}
      {(connecting || error) && (
        <a-entity position="0 0 0.02">
          <a-plane
            width="2"
            height="1.5"
            material="color: black; opacity: 0.8"
          />
          <a-text
            value={connecting ? 'Connecting to VNC...' : `Error: ${error}`}
            align="center"
            position="0 0.2 0.01"
            color="white"
            width="8"
          />
          {error && (
            <a-box
              width="0.6"
              height="0.2"
              depth="0.05"
              position="0 -0.2 0.01"
              material="color: #4A90E2"
              text="value: Retry; align: center; color: white; width: 16"
              cursor-listener=""
              onClick={handleReconnect}
            />
          )}
        </a-entity>
      )}

      {/* Control indicator */}
      {connected && (
        <a-entity position="0.8 0.6 0.02">
          <a-box
            width="0.4"
            height="0.1"
            depth="0.02"
            material={`color: ${hasControl ? '#4CAF50' : '#FFC107'}`}
          />
          <a-text
            value={hasControl ? '🎮 VR Control' : '👆 VR Touch'}
            align="center"
            position="0 0 0.01"
            color="white"
            width="12"
          />
        </a-entity>
      )}

      {/* Debug info for VR */}
      {process.env.NODE_ENV === 'development' && (
        <a-text
          value={`VR Instance: ${instanceId} | Connected: ${connected ? '✓' : '✗'} | Control: ${hasControl ? '✓' : '✗'}`}
          position="0 -0.8 0.01"
          align="center"
          color="#00FF00"
          width="6"
        />
      )}
      
      {/* VNC Component Mount Point - This will need custom integration */}
      <a-entity 
        id={`vnc-mount-${instanceId}`}
        position="0 0 0.001"
        vnc-component={`url: ${vncUrl}; instance: ${instanceId}`}
      />
    </a-entity>
  );
}
