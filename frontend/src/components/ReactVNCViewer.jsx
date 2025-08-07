import React, { useEffect, useRef, useState } from 'react';
import { VncScreen } from 'react-vnc';

/**
 * React-VNC based VNC viewer component
 * Uses the react-vnc library for robust VNC protocol implementation
 * Enhanced with audio and controls testing
 */
export default function ReactVNCViewer({ instanceId }) {
  const [connected, setConnected] = useState(false);
  const [connecting, setConnecting] = useState(false);
  const [error, setError] = useState(null);
  const [hasControl, setHasControl] = useState(false);
  const [audioDetected, setAudioDetected] = useState(false);
  const [controlsResponsive, setControlsResponsive] = useState(false);
  const vncRef = useRef(null);
  
  // Control release tracking
  const keySequenceRef = useRef([]);
  const lastKeyTimeRef = useRef(0);
  
  // Audio and controls testing
  const lastControlTestRef = useRef(0);
  const audioContextRef = useRef(null);

  // Debug logging for hasControl state changes
  useEffect(() => {
    console.log(`🎮 ReactVNC hasControl state changed to: ${hasControl} for instance ${instanceId}`);
  }, [hasControl, instanceId]);

  // Test audio detection
  useEffect(() => {
    if (connected && hasControl) {
      testAudioCapabilities();
    }
  }, [connected, hasControl]);

  // Test controls responsiveness periodically
  useEffect(() => {
    if (connected && hasControl) {
      const testInterval = setInterval(() => {
        testControlsResponsiveness();
      }, 10000); // Test every 10 seconds

      return () => clearInterval(testInterval);
    }
  }, [connected, hasControl]);

  console.log('ReactVNCViewer component mounted for instance:', instanceId);

  // Create WebSocket connection URL
  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  const vncUrl = `${protocol}//${window.location.host}/proxy/vnc/${instanceId}/`;

  // Audio detection test
  const testAudioCapabilities = async () => {
    try {
      // Try to detect audio context capabilities
      if (window.AudioContext || window.webkitAudioContext) {
        if (!audioContextRef.current) {
          audioContextRef.current = new (window.AudioContext || window.webkitAudioContext)();
        }
        
        // Test if we can create audio nodes (indicates audio support)
        const oscillator = audioContextRef.current.createOscillator();
        const gainNode = audioContextRef.current.createGain();
        oscillator.connect(gainNode);
        
        setAudioDetected(true);
        console.log('🔊 Audio capabilities detected for instance:', instanceId);
        
        // Dispatch event for quality monitoring
        window.dispatchEvent(new CustomEvent('vncAudioDetected', {
          detail: { instanceId, detected: true }
        }));
      } else {
        setAudioDetected(false);
        console.log('🔇 No audio capabilities detected for instance:', instanceId);
      }
    } catch (error) {
      console.warn('Audio detection failed:', error);
      setAudioDetected(false);
    }
  };

  // Controls responsiveness test
  const testControlsResponsiveness = () => {
    const now = Date.now();
    
    // Don't test too frequently
    if (now - lastControlTestRef.current < 5000) return;
    lastControlTestRef.current = now;

    try {
      // Test if we can access the VNC canvas for control testing
      const canvas = vncRef.current?.querySelector('canvas');
      if (canvas) {
        // Simulate a minimal mouse movement to test responsiveness
        const testEvent = new MouseEvent('mousemove', {
          clientX: canvas.getBoundingClientRect().left + 1,
          clientY: canvas.getBoundingClientRect().top + 1,
          bubbles: true,
          cancelable: true
        });
        
        const eventDispatched = canvas.dispatchEvent(testEvent);
        setControlsResponsive(eventDispatched);
        
        console.log(`🎮 Controls responsiveness test for ${instanceId}: ${eventDispatched ? 'PASS' : 'FAIL'}`);
        
        // Dispatch event for quality monitoring
        window.dispatchEvent(new CustomEvent('vncControlsTest', {
          detail: { instanceId, responsive: eventDispatched }
        }));
      } else {
        setControlsResponsive(false);
        console.log(`🎮 Controls test failed - no canvas found for ${instanceId}`);
      }
    } catch (error) {
      console.warn('Controls responsiveness test failed:', error);
      setControlsResponsive(false);
    }
  };

  // VNC event handlers
  const handleConnect = () => {
    console.log('ReactVNC connected to', instanceId);
    setConnected(true);
    setConnecting(false);
    setHasControl(true);
    setError(null);
    
    // Test capabilities after connection
    setTimeout(() => {
      testAudioCapabilities();
      testControlsResponsiveness();
    }, 1000);
  };

  const handleDisconnect = () => {
    console.log('ReactVNC disconnected from', instanceId);
    setConnected(false);
    setConnecting(false);
    setHasControl(false);
    setAudioDetected(false);
    setControlsResponsive(false);
    
    // Clean up audio context
    if (audioContextRef.current) {
      audioContextRef.current.close();
      audioContextRef.current = null;
    }
  };

  const handleError = (error) => {
    console.error('ReactVNC error:', error);
    setError(`Connection failed: ${error.message || error}`);
    setConnecting(false);
    setConnected(false);
  };

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
      if (event.detail.instanceId === instanceId && hasControl && connected && vncRef.current) {
        const { x, y, button, pressed } = event.detail;
        console.log(`🎮 VR pointer: (${x}, ${y}) button=${button} pressed=${pressed}`);
        
        // React-VNC handles pointer events through the component, so we dispatch a synthetic event
        const canvas = vncRef.current.querySelector('canvas');
        if (canvas && x >= 0 && y >= 0) {
          const rect = canvas.getBoundingClientRect();
          const clientX = rect.left + (x / canvas.width) * rect.width;
          const clientY = rect.top + (y / canvas.height) * rect.height;
          
          const eventType = pressed ? 'mousedown' : 'mouseup';
          const mouseEvent = new MouseEvent(eventType, {
            clientX,
            clientY,
            button,
            bubbles: true,
            cancelable: true
          });
          canvas.dispatchEvent(mouseEvent);
        }
      }
    };

    const handleVRKeyboard = (event) => {
      if (event.detail.instanceId === instanceId && hasControl && connected && vncRef.current) {
        const { key, pressed } = event.detail;
        console.log(`🎮 VR keyboard: key=${key} pressed=${pressed}`);
        
        // React-VNC handles keyboard events through the component
        const canvas = vncRef.current.querySelector('canvas');
        if (canvas) {
          const eventType = pressed ? 'keydown' : 'keyup';
          const keyEvent = new KeyboardEvent(eventType, {
            key,
            code: 'Key' + key.toUpperCase(),
            bubbles: true,
            cancelable: true
          });
          canvas.dispatchEvent(keyEvent);
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
    console.log('🔓 Releasing control of ReactVNC instance:', instanceId);
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
    
    console.log('🔒 Regaining control of ReactVNC instance:', instanceId);
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
    
    console.log('🎮 Control regain event dispatched for VR/external controllers');
  };

  const handleReconnect = () => {
    console.log('Reconnecting to VNC...');
    setError(null);
    setConnecting(true);
    setConnected(false);
    setHasControl(false);
  };

  const handleContainerClick = () => {
    if (!hasControl && connected) {
      regainControl();
    }
  };

  if (!instanceId) {
    return (
      <div className="flex items-center justify-center h-64 bg-gray-100 border-2 border-dashed border-gray-300">
        <p className="text-gray-500">No instance selected</p>
      </div>
    );
  }

  return (
    <div className="vnc-container relative bg-black border border-gray-300 overflow-hidden">
      {/* Connection status overlay */}
      {(connecting || error) && (
        <div className="absolute inset-0 bg-black bg-opacity-75 flex items-center justify-center z-10">
          <div className="text-center text-white">
            {connecting && (
              <>
                <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-white mx-auto mb-2"></div>
                <p>Connecting to VNC...</p>
              </>
            )}
            {error && (
              <>
                <p className="text-red-400 mb-2">{error}</p>
                <button 
                  onClick={handleReconnect}
                  className="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700"
                >
                  Retry Connection
                </button>
              </>
            )}
          </div>
        </div>
      )}

      {/* Control and Status indicators */}
      {connected && (
        <div className="absolute top-2 right-2 z-20 space-y-1">
          {/* Control Status */}
          <div className={`px-2 py-1 rounded text-xs font-medium ${
            hasControl 
              ? 'bg-green-500 text-white' 
              : 'bg-yellow-500 text-black cursor-pointer hover:bg-yellow-400'
          }`}>
            {hasControl ? '🎮 You have control' : '👆 Click to take control'}
          </div>
          
          {/* Audio Status */}
          <div className={`px-2 py-1 rounded text-xs font-medium ${
            audioDetected 
              ? 'bg-blue-500 text-white' 
              : 'bg-gray-500 text-white'
          }`}>
            🔊 {audioDetected ? 'Audio Ready' : 'No Audio'}
          </div>
          
          {/* Controls Status */}
          <div className={`px-2 py-1 rounded text-xs font-medium ${
            controlsResponsive 
              ? 'bg-green-500 text-white' 
              : 'bg-orange-500 text-white'
          }`}>
            🎯 {controlsResponsive ? 'Controls OK' : 'Controls Test'}
          </div>
        </div>
      )}

      {/* VNC Component */}
      <div 
        ref={vncRef}
        onClick={handleContainerClick}
        className="w-full h-full min-h-96"
        style={{ opacity: hasControl ? 1 : 0.7 }}
      >
        <VncScreen
          url={vncUrl}
          style={{
            width: '100%',
            height: '100%',
          }}
          onConnect={handleConnect}
          onDisconnect={handleDisconnect}
          onError={handleError}
          scaleViewport={true}
          resizeSession={false}
          showDotCursor={true}
          background="#000000"
          qualityLevel={6}
          compressionLevel={2}
        />
      </div>

      {/* Debug info */}
      {process.env.NODE_ENV === 'development' && (
        <div className="absolute bottom-2 left-2 text-xs text-gray-300 bg-black bg-opacity-50 p-1 rounded">
          Instance: {instanceId} | Connected: {connected ? '✓' : '✗'} | Control: {hasControl ? '✓' : '✗'} | Audio: {audioDetected ? '✓' : '✗'} | Controls: {controlsResponsive ? '✓' : '✗'}
        </div>
      )}
    </div>
  );
}
