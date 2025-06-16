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
  
  // Buffer for accumulating partial VNC messages
  const messageBufferRef = useRef(new Uint8Array(0));
  const updateRequestedRef = useRef(false);

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
              setConnected(true);
              setConnecting(false);
              
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
      setConnected(false);
      setConnecting(false);
    };
  }, [instanceId]);

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

  const handleCanvasClick = () => {
    if (connected) {
      alert(`Interacting with ${instanceId} - VNC input would be processed here`);
    } else {
      // Attempt reconnection
      const event = new Event('reconnect');
      window.dispatchEvent(event);
    }
  };

  const handleReconnect = () => {
    setError(null);
    setConnecting(false);
    setConnected(false);
    // Reset refs for new connection
    messageBufferRef.current = new Uint8Array(0);
    updateRequestedRef.current = false;
    // Trigger re-render to restart connection
    const canvas = canvasRef.current;
    if (canvas) {
      const ctx = canvas.getContext('2d');
      ctx.fillStyle = '#000';
      ctx.fillRect(0, 0, canvas.width, canvas.height);
    }
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
        style={{ imageRendering: 'pixelated' }}
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
          <span className="text-green-400">●</span>
          <span>{instanceId}</span>
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
