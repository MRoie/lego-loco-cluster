import React, { useEffect, useRef, useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { createLogger } from '../utils/logger.js';
import { metrics } from '../utils/metrics';

/**
 * NoVNC-based VNC viewer component
 * Uses the noVNC library for robust VNC protocol implementation
 */
export default function NoVNCViewer({ instanceId }) {
  const logger = createLogger('NoVNCViewer');
  const containerRef = useRef(null);
  const rfbRef = useRef(null);
  const [connected, setConnected] = useState(false);
  const [connecting, setConnecting] = useState(false);
  const [error, setError] = useState(null);
  const [hasControl, setHasControl] = useState(false);
  const [framebufferSize, setFramebufferSize] = useState(null);
  const [RFB, setRFB] = useState(null);
  const [showOverlays, setShowOverlays] = useState(true);
  const idleTimerRef = useRef(null);

  // Control release tracking
  const keySequenceRef = useRef([]);
  const lastKeyTimeRef = useRef(0);

  // Load NoVNC RFB class dynamically to avoid top-level await issues
  useEffect(() => {
    const loadNoVNC = async () => {
      try {
        logger.debug('Loading NoVNC RFB module');
        const novncModule = await import('@novnc/novnc/lib/rfb.js');
        const RFBClass = novncModule.default || novncModule.RFB;
        setRFB(() => RFBClass);
        logger.info('NoVNC RFB module loaded successfully');
      } catch (err) {
        logger.error('Failed to load NoVNC', { error: err.message, instanceId });
        setError(`Failed to load NoVNC: ${err.message}`);
      }
    };

    loadNoVNC();
  }, []);

  // Debug logging for hasControl state changes
  useEffect(() => {
    logger.debug('NoVNC hasControl state changed', { hasControl, instanceId });
  }, [hasControl, instanceId]);

  console.log('[NoVNCViewer] Component mounted', { instanceId });
  logger.debug('NoVNCViewer component mounted', { instanceId });
  metrics.incrementCounter('novnc_viewer_mount', { instance: instanceId });

  useEffect(() => {
    if (!instanceId || !containerRef.current || !RFB) {
      logger.debug('Missing dependencies for NoVNC initialization', {
        instanceId: !!instanceId,
        container: !!containerRef.current,
        RFB: !!RFB
      });
      return;
    }

    logger.info('Starting NoVNC connection', { instanceId });
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

    logger.debug('Connecting to VNC URL', { vncUrl, instanceId });

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
        console.log('[NoVNCViewer] ✅ VNC CONNECTED!', { instanceId });
        logger.info('NoVNC connected successfully', { instanceId });
        setConnected(true);
        setConnecting(false);
        setHasControl(true);
        setError(null);
        metrics.incrementCounter('novnc_connection_success', { instance: instanceId });

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
        console.log('[NoVNCViewer] ❌ VNC DISCONNECTED', { instanceId, clean: e.detail.clean });
        logger.info('NoVNC disconnected', { instanceId, clean: e.detail.clean, reason: e.detail });
        setConnected(false);
        setConnecting(false);
        setHasControl(false);
        metrics.incrementCounter('novnc_disconnect', { instance: instanceId });

        if (!e.detail.clean) {
          setError('Connection lost');
        }
      });

      rfb.addEventListener('credentialsrequired', () => {
        console.log('[NoVNCViewer] 🔐 VNC CREDENTIALS REQUIRED', { instanceId });
        logger.warn('VNC credentials required', { instanceId });
        setError('VNC server requires authentication');
        setConnecting(false);
        metrics.incrementCounter('novnc_credentials_required', { instance: instanceId });
      });

      rfb.addEventListener('securityfailure', (e) => {
        console.error('[NoVNCViewer] 🚨 VNC SECURITY FAILURE', { instanceId, detail: e.detail });
        logger.error('VNC security failure', { instanceId, detail: e.detail });
        setError('VNC security failure');
        setConnecting(false);
        metrics.incrementCounter('novnc_security_failure', { instance: instanceId });
      });

      rfb.addEventListener('bell', () => {
        logger.debug('VNC bell signal received', { instanceId });
      });

      rfb.addEventListener('desktopname', (e) => {
        console.log('[NoVNCViewer] 🖥️  VNC DESKTOP NAME RECEIVED', { instanceId, desktopName: e.detail.name });
        logger.debug('VNC desktop name received', { instanceId, desktopName: e.detail.name });
        metrics.incrementCounter('novnc_desktop_name', { instance: instanceId });
      });

      // Configure noVNC options
      rfb.scaleViewport = true;
      rfb.resizeSession = false;
      rfb.showDotCursor = true;
      rfb.background = '#000000';
      rfb.qualityLevel = 6;
      rfb.compressionLevel = 2;

    } catch (err) {
      console.error('[NoVNCViewer] ⚠️ VNC ERROR', { instanceId, error: err.message, fullError: err });
      logger.error('Failed to create NoVNC RFB', { instanceId, error: err.message });
      setError(`Connection failed: ${err.message}`);
      setConnecting(false);
      metrics.incrementCounter('novnc_error', { instance: instanceId });
    }

    // Cleanup function
    return () => {
      console.log('[NoVNCViewer] Component unmounting', { instanceId });
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
      if (event.detail.instanceId === instanceId && hasControl && connected && rfbRef.current) {
        const { x, y, button, pressed } = event.detail;
        logger.debug('VR pointer event received', { instanceId, x, y, button, pressed });

        if (x >= 0 && y >= 0) {
          const buttonMask = pressed ? (1 << button) : 0;
          try {
            rfbRef.current.sendPointerEvent(x, y, buttonMask);
          } catch (error) {
            logger.error('Error sending VR pointer event', { instanceId, error: error.message });
          }
        }
      }
    };

    const handleVRKeyboard = (event) => {
      if (event.detail.instanceId === instanceId && hasControl && connected && rfbRef.current) {
        const { key, pressed } = event.detail;
        logger.debug('VR keyboard event received', { instanceId, key, pressed });

        try {
          // Convert VR key to keySym (basic implementation)
          const keySym = getKeySymbol({ key, code: key });
          if (keySym > 0) {
            rfbRef.current.sendKey(keySym, 'Key' + key, pressed);
          }
        } catch (error) {
          logger.error('Error sending VR keyboard event', { instanceId, error: error.message });
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
    logger.info('Releasing control of NoVNC instance', { instanceId });
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

    logger.debug('Control release event dispatched for VR/external controllers', { instanceId });
  };

  // Regain control of this instance
  const regainControl = () => {
    logger.debug('regainControl called', { instanceId, connected, currentControl: hasControl });

    if (!connected) {
      logger.warn('Cannot regain control: VNC not connected', { instanceId });
      return;
    }

    logger.info('Regaining control of NoVNC instance', { instanceId });
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
      logger.debug('Canvas focused for keyboard input', { instanceId });
    }

    logger.debug('Control regain event dispatched for VR/external controllers', { instanceId });
    logger.info('Control regained successfully', { instanceId, hasControl: true });
  };

  const handleReconnect = () => {
    logger.debug('handleReconnect called - triggering reconnection', { instanceId });
    setError(null);

    // Trigger reconnection by changing a dependency
    setConnecting(true);
  };

  const handleContainerClick = () => {
    if (!connected) {
      logger.debug('Container clicked - attempting to connect', { instanceId });
      handleReconnect();
      return;
    }

    if (!hasControl) {
      logger.debug('Container clicked - regaining control', { instanceId });
      regainControl();
    }
  };

  const resetIdleTimer = () => {
    setShowOverlays(true);
    if (idleTimerRef.current) clearTimeout(idleTimerRef.current);
    idleTimerRef.current = setTimeout(() => {
      // Only hide if connected and no error
      if (connected && !error) {
        setShowOverlays(false);
      }
    }, 15000); // Hide after 15 seconds of inactivity
  };

  // Only trigger on entry, not on every pixel move
  // This prevents overlays from flickering or persisting while user is working
  const handleContainerEnter = () => {
    resetIdleTimer();
  };

  // Initial timer setup
  useEffect(() => {
    resetIdleTimer();
    return () => {
      if (idleTimerRef.current) clearTimeout(idleTimerRef.current);
    };
  }, [connected, error]);

  return (
    <div
      className="relative w-full h-full bg-black rounded-lg overflow-hidden group"
      onMouseEnter={handleContainerEnter}
      onTouchStart={resetIdleTimer}
    >
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

      <AnimatePresence>
        {/* Status Indicators */}
        {connecting && (
          <motion.div
            initial={{ opacity: 0, y: -10 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0 }}
            className="absolute top-2 left-2 bg-blue-500 text-white px-2 py-1 rounded text-xs pointer-events-none"
          >
            <div className="animate-pulse">Connecting...</div>
          </motion.div>
        )}

        {connected && showOverlays && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0, transition: { duration: 0.5 } }}
            className="absolute top-2 left-2 bg-green-500 text-white px-2 py-1 rounded text-xs font-semibold pointer-events-none"
          >
            <div>NoVNC Connected</div>
            {framebufferSize && (
              <div className="text-xs opacity-90">
                {framebufferSize.width}×{framebufferSize.height}
              </div>
            )}
          </motion.div>
        )}

        {error && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            className="absolute inset-0 flex items-center justify-center bg-black bg-opacity-75 z-50"
          >
            <div className="bg-red-600 text-white px-4 py-2 rounded-lg text-center max-w-sm">
              <div className="font-semibold mb-2">Connection Error</div>
              <div className="text-sm mb-3">{error}</div>
              <button
                onClick={handleReconnect}
                className="bg-red-700 hover:bg-red-800 px-3 py-1 rounded text-sm pointer-events-auto"
              >
                Retry Connection
              </button>
            </div>
          </motion.div>
        )}

        {/* Control Panel */}
        {connected && showOverlays && (
          <motion.div
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: 20, transition: { duration: 0.5 } }}
            className="absolute top-2 right-2 bg-black bg-opacity-75 rounded-lg p-2 flex items-center space-x-2 text-white text-xs pointer-events-none"
          >
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
          </motion.div>
        )}

        {/* Input Instructions */}
        {connected && hasControl && showOverlays && (
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: 20, transition: { duration: 0.5 } }}
            className="absolute bottom-2 left-2 bg-black bg-opacity-75 rounded-lg p-2 text-white text-xs max-w-xs pointer-events-none"
          >
            <div className="font-semibold mb-1">NoVNC Controls:</div>
            <div>• Full mouse and keyboard support</div>
            <div className="mt-2 text-yellow-400">
              <div className="font-semibold">Release Control:</div>
              <div>• Ctrl+Alt+R (primary)</div>
            </div>
          </motion.div>
        )}

        {/* No Control Overlay - Only show if overlays are active OR force it? User said "avoid hiding". 
            Maybe fading this one too is good, as long as they can click to regain. 
            We will make it fade but reappear on hover.
        */}
        {connected && !hasControl && showOverlays && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="absolute bottom-2 right-2 bg-orange-600 bg-opacity-90 rounded-lg p-2 text-white text-xs pointer-events-auto cursor-pointer"
            onClick={regainControl}
            whileHover={{ scale: 1.05 }}
          >
            <div className="font-bold">🔓 Click to Take Control</div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Debug Controls (remove in production) */}
      {process.env.NODE_ENV === 'development' && (
        <div className="absolute bottom-2 right-2 bg-red-800 bg-opacity-75 rounded-lg p-2 text-white text-xs">
          <div className="font-semibold mb-1">Debug Controls:</div>
          <button
            className="bg-blue-600 hover:bg-blue-700 px-2 py-1 rounded text-xs mr-1"
            onClick={() => {
              logger.debug('Force regain control triggered', { instanceId });
              regainControl();
            }}
          >
            Force Regain
          </button>
          <button
            className="bg-orange-600 hover:bg-orange-700 px-2 py-1 rounded text-xs mr-1"
            onClick={() => {
              logger.debug('Force release control triggered', { instanceId });
              releaseControl();
            }}
          >
            Force Release
          </button>
          <button
            className="bg-gray-600 hover:bg-gray-700 px-2 py-1 rounded text-xs"
            onClick={() => {
              logger.debug('Current NoVNC state', {
                instanceId,
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
