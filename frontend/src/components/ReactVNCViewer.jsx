import React, { useEffect, useRef, useState, useCallback } from 'react';
import { VncScreen } from 'react-vnc';
import { useVNCConnection, ConnectionState } from '../hooks/useVNCConnection';
import { createLogger } from '../utils/logger';
import { metrics } from '../utils/metrics';
import VNCDebugPanel from './VNCDebugPanel';

const logger = createLogger('ReactVNCViewer');

/**
 * React-VNC based VNC viewer component
 * Uses the react-vnc library for robust VNC protocol implementation
 * Enhanced with audio, controls testing, and enterprise-grade observability
 */
export default function ReactVNCViewer({ instanceId }) {
  // Use robust connection hook
  const { state, connect, disconnect, updateState } = useVNCConnection(instanceId, {
    autoConnect: true,
    retryAttempts: 5,
    onConnectionChange: (newState) => {
      logger.info('Connection state changed', { instanceId, newState });
      metrics.incrementCounter('vnc_state_change', { instance: instanceId, state: newState });
    },
    onError: (error) => {
      // Error logging handled by hook, but we can add component-specific logic here
    }
  });

  const { connectionState, vncUrl, instance, error } = state;

  // Local state for features not managed by connection hook
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
    logger.debug(`Control state changed`, { instanceId, hasControl });
    metrics.setGauge('vnc_has_control', hasControl ? 1 : 0, { instance: instanceId });
  }, [hasControl, instanceId]);

  // Test audio detection
  useEffect(() => {
    if (connectionState === ConnectionState.CONNECTED && hasControl) {
      testAudioCapabilities();
    }
  }, [connectionState, hasControl]);

  // Test controls responsiveness periodically
  useEffect(() => {
    if (connectionState === ConnectionState.CONNECTED && hasControl) {
      const testInterval = setInterval(() => {
        testControlsResponsiveness();
      }, 10000); // Test every 10 seconds

      return () => clearInterval(testInterval);
    }
  }, [connectionState, hasControl]);

  useEffect(() => {
    console.log('[ReactVNCViewer] Component mounted', { instanceId });
    logger.info('Component mounted', { instanceId });
    metrics.incrementCounter('vnc_viewer_mount', { instance: instanceId });
    return () => {
      console.log('[ReactVNCViewer] Component unmounted', { instanceId });
      logger.info('Component unmounted', { instanceId });
    };
  }, [instanceId]);

  // Debug: Log state changes
  useEffect(() => {
    console.log('[ReactVNCViewer] State changed', {
      instanceId,
      connectionState,
      vncUrl,
      hasError: !!error,
      hasInstance: !!instance
    });
  }, [instanceId, connectionState, vncUrl, error, instance]);

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
        logger.info('Audio capabilities detected', { instanceId });
        metrics.setGauge('vnc_audio_detected', 1, { instance: instanceId });

        // Dispatch event for quality monitoring
        window.dispatchEvent(new CustomEvent('vncAudioDetected', {
          detail: { instanceId, detected: true }
        }));
      } else {
        setAudioDetected(false);
        logger.warn('No audio capabilities detected', { instanceId });
        metrics.setGauge('vnc_audio_detected', 0, { instance: instanceId });
      }
    } catch (error) {
      logger.warn('Audio detection failed', { instanceId, error: error.message });
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

        logger.debug('Controls responsiveness test', { instanceId, result: eventDispatched ? 'PASS' : 'FAIL' });
        metrics.incrementCounter('vnc_controls_test', { instance: instanceId, result: eventDispatched ? 'pass' : 'fail' });

        // Dispatch event for quality monitoring
        window.dispatchEvent(new CustomEvent('vncControlsTest', {
          detail: { instanceId, responsive: eventDispatched }
        }));
      } else {
        setControlsResponsive(false);
        logger.debug('Controls test failed - no canvas found', { instanceId });
      }
    } catch (error) {
      logger.warn('Controls responsiveness test failed', { instanceId, error: error.message });
      setControlsResponsive(false);
    }
  };

  // VNC event handlers
  const handleConnect = useCallback(() => {
    console.log('[ReactVNCViewer] ✅ VNC CONNECTED!', { instanceId });
    logger.info('VNC connected successfully', { instanceId });
    updateState({ connectionState: ConnectionState.CONNECTED });
    setHasControl(true);

    metrics.incrementCounter('vnc_connection_success', { instance: instanceId });

    // Test capabilities after connection
    setTimeout(() => {
      testAudioCapabilities();
      testControlsResponsiveness();
    }, 1000);
  }, [instanceId, updateState]);

  const handleDisconnect = useCallback(() => {
    console.log('[ReactVNCViewer] ❌ VNC DISCONNECTED', { instanceId });
    logger.info('VNC disconnected', { instanceId });
    updateState({ connectionState: ConnectionState.DISCONNECTED });
    setHasControl(false);
    setAudioDetected(false);
    setControlsResponsive(false);

    metrics.incrementCounter('vnc_disconnect', { instance: instanceId });

    // Clean up audio context
    if (audioContextRef.current) {
      audioContextRef.current.close();
      audioContextRef.current = null;
    }
  }, [instanceId, updateState]);

  const handleError = useCallback((error) => {
    console.error('[ReactVNCViewer] ⚠️ VNC ERROR', { instanceId, error: error.message || error, fullError: error });
    logger.error('VNC error occurred', { instanceId, error: error.message || error });
    // Note: We don't set FAILED state here immediately because react-vnc might retry internally
    // or it might be a transient error. But we log it.
    // If it's a fatal error, the hook's retry logic should handle reconnection if needed.
    metrics.incrementCounter('vnc_error', { instance: instanceId });
  }, [instanceId]);

  // Credential handler - VNC server might require authentication
  const handleCredentialsRequired = useCallback(() => {
    console.log('[ReactVNCViewer] 🔐 VNC CREDENTIALS REQUIRED', { instanceId });
    logger.info('VNC credentials required', { instanceId });
    // For now, we don't have credentials configured
    // If needed in the future, we can prompt the user or use stored credentials
    metrics.incrementCounter('vnc_credentials_required', { instance: instanceId });
  }, [instanceId]);

  // Security failure handler
  const handleSecurityFailure = useCallback((error) => {
    logger.error('VNC security failure', { instanceId, error });
    updateState({
      connectionState: ConnectionState.FAILED,
      error: `Security failure: ${error?.detail || 'Authentication failed'}`
    });
    metrics.incrementCounter('vnc_security_failure', { instance: instanceId });
  }, [instanceId, updateState]);

  // Desktop name handler - indicates successful connection
  const handleDesktopName = useCallback((name) => {
    console.log('[ReactVNCViewer] 🖥️  VNC DESKTOP NAME RECEIVED', { instanceId, desktopName: name?.detail });
    logger.info('VNC desktop name received', { instanceId, desktopName: name?.detail });
    metrics.incrementCounter('vnc_desktop_name', { instance: instanceId });
  }, [instanceId]);

  // Clipboard handler
  const handleClipboard = useCallback((event) => {
    logger.debug('VNC clipboard event', { instanceId });
  }, [instanceId]);

  // Bell handler
  const handleBell = useCallback(() => {
    logger.debug('VNC bell event', { instanceId });
  }, [instanceId]);

  // Capabilities handler
  const handleCapabilities = useCallback((capabilities) => {
    console.log('[ReactVNCViewer] 🎯 VNC CAPABILITIES RECEIVED', { instanceId, capabilities: capabilities?.detail });
    logger.info('VNC capabilities received', { instanceId, capabilities: capabilities?.detail });
  }, [instanceId]);

  // VR Controller Support - Listen for VR events
  useEffect(() => {
    // VR trigger button handler (for regaining control)
    const handleVRTrigger = (event) => {
      if (event.detail.instanceId === instanceId && !hasControl && connectionState === ConnectionState.CONNECTED) {
        logger.debug('VR trigger detected for control regain', { instanceId });
        regainControl();
      }
    };

    // VR release gesture handler (for releasing control)
    const handleVRRelease = (event) => {
      if (event.detail.instanceId === instanceId && hasControl) {
        logger.debug('VR release gesture detected', { instanceId });
        releaseControl();
      }
    };

    // VR input events (pointer/keyboard from VR controllers)
    const handleVRPointer = (event) => {
      if (event.detail.instanceId === instanceId && hasControl && connectionState === ConnectionState.CONNECTED && vncRef.current) {
        const { x, y, button, pressed } = event.detail;

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
      if (event.detail.instanceId === instanceId && hasControl && connectionState === ConnectionState.CONNECTED && vncRef.current) {
        const { key, pressed } = event.detail;

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
  }, [instanceId, hasControl, connectionState]);

  // Keyboard event handler for control release sequences
  useEffect(() => {
    const handleKeyDown = (event) => {
      if (connectionState !== ConnectionState.CONNECTED || !hasControl) return;

      // Check for control release sequence
      if (checkControlReleaseSequence(event)) {
        logger.info('Control release sequence detected', { instanceId });
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
  }, [connectionState, hasControl]);

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
      ['Control', 'Alt', 'KeyR'],
      ['Control', 'Shift', 'Escape'],
      ['F10', 'F10', 'F10'],
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
    logger.info('Releasing control', { instanceId });
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
  };

  // Regain control of this instance
  const regainControl = () => {
    if (connectionState !== ConnectionState.CONNECTED) {
      logger.debug('Cannot regain control: VNC not connected', { instanceId });
      return;
    }

    logger.info('Regaining control', { instanceId });
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
  };

  const handleReconnect = () => {
    logger.info('Manual reconnection requested', { instanceId });
    metrics.incrementCounter('vnc_manual_reconnect', { instance: instanceId });
    connect();
  };

  const handleContainerClick = () => {
    if (!hasControl && connectionState === ConnectionState.CONNECTED) {
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

  // Determine if we should show loading/connecting state
  const isConnecting =
    connectionState === ConnectionState.CONNECTING ||
    connectionState === ConnectionState.FETCHING_METADATA ||
    connectionState === ConnectionState.AUTHENTICATING ||
    connectionState === ConnectionState.RECONNECTING;

  // Determine if we are in a failed state
  const isFailed = connectionState === ConnectionState.FAILED;

  return (
    <div className="vnc-container relative bg-black border border-gray-300 overflow-hidden">
      {/* Connection status overlay */}
      {(isConnecting || isFailed) && (
        <div className="absolute inset-0 bg-black bg-opacity-75 flex items-center justify-center z-10">
          <div className="text-center text-white">
            {isConnecting && (
              <>
                <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-white mx-auto mb-2"></div>
                <p>
                  {connectionState === ConnectionState.RECONNECTING ? 'Reconnecting...' : 'Connecting to VNC...'}
                </p>
                {state.retryCount > 0 && (
                  <p className="text-xs text-gray-400 mt-1">Attempt {state.retryCount}</p>
                )}
              </>
            )}
            {isFailed && (
              <>
                <p className="text-red-400 mb-2">Connection Failed</p>
                <p className="text-xs text-gray-400 mb-4 max-w-xs mx-auto">{error?.message || 'Unknown error'}</p>
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
      {connectionState === ConnectionState.CONNECTED && (
        <div className="absolute top-2 right-2 z-20 space-y-1">
          {/* Control Status */}
          <div className={`px-2 py-1 rounded text-xs font-medium ${hasControl
            ? 'bg-green-500 text-white'
            : 'bg-yellow-500 text-black cursor-pointer hover:bg-yellow-400'
            }`}>
            {hasControl ? '🎮 You have control' : '👆 Click to take control'}
          </div>

          {/* Audio Status */}
          <div className={`px-2 py-1 rounded text-xs font-medium ${audioDetected
            ? 'bg-blue-500 text-white'
            : 'bg-gray-500 text-white'
            }`}>
            🔊 {audioDetected ? 'Audio Ready' : 'No Audio'}
          </div>

          {/* Controls Status */}
          <div className={`px-2 py-1 rounded text-xs font-medium ${controlsResponsive
            ? 'bg-green-500 text-white'
            : 'bg-orange-500 text-white'
            }`}>
            🎯 {controlsResponsive ? 'Controls OK' : 'Controls Test'}
          </div>
        </div>
      )}

      {/* VNC Component */}
      {console.log('[ReactVNCViewer] Rendering VncScreen', { vncUrl, hasVncUrl: !!vncUrl, connectionState })}
      <div
        ref={vncRef}
        onClick={handleContainerClick}
        className="w-full h-full min-h-96"
        style={{ opacity: hasControl ? 1 : 0.7 }}
      >
        {vncUrl && (
          <VncScreen
            url={vncUrl}
            style={{
              width: '100%',
              height: '100%',
            }}
            // Connection handlers
            onConnect={handleConnect}
            onDisconnect={handleDisconnect}
            onError={handleError}
            onCredentialsRequired={handleCredentialsRequired}
            onSecurityFailure={handleSecurityFailure}
            onDesktopName={handleDesktopName}
            onClipboard={handleClipboard}
            onBell={handleBell}
            onCapabilities={handleCapabilities}
            // Display options
            scaleViewport={true}
            resizeSession={false}
            showDotCursor={true}
            background="#000000"
            focusOnClick={true}
            // Quality settings
            qualityLevel={6}
            compressionLevel={2}
            // Connection behavior
            autoConnect={true}
            retryDuration={3000}
            debug={true}
          />
        )}
      </div>

      {/* Debug Panel */}
      <VNCDebugPanel instanceId={instanceId} state={state} />
    </div>
  );
}
