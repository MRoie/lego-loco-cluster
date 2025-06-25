#!/usr/bin/env node

const WebSocket = require('ws');

console.log('Testing VNC WebSocket connection...');

// Connect to the VNC proxy
const ws = new WebSocket('ws://localhost:3001/proxy/vnc/instance-0/');

let handshakeStep = 0;

ws.on('open', () => {
    console.log('WebSocket connected');
});

ws.on('message', (data) => {
    console.log(`Step ${handshakeStep}: Received ${data.length} bytes:`, data);
    
    if (handshakeStep === 0) {
        // VNC server version - respond with client version
        const serverVersion = data.toString();
        console.log('Server version:', JSON.stringify(serverVersion));
        
        const clientVersion = 'RFB 003.008\n';
        console.log('Sending client version:', JSON.stringify(clientVersion));
        ws.send(clientVersion);
        handshakeStep = 1;
        
    } else if (handshakeStep === 1) {
        // Security types
        console.log('Security types received');
        const numTypes = data[0];
        console.log('Number of security types:', numTypes);
        
        if (numTypes > 0) {
            for (let i = 0; i < numTypes; i++) {
                console.log(`Security type ${i}: ${data[1 + i]}`);
            }
            
            // Select "None" security (type 1)
            console.log('Selecting security type 1 (None)');
            ws.send(Buffer.from([1]));
            handshakeStep = 2;
        }
        
    } else if (handshakeStep === 2) {
        // Security result
        const result = data.readUInt32BE(0);
        console.log('Security result:', result);
        
        if (result === 0) {
            console.log('Security handshake successful');
            console.log('Sending ClientInit (shared=1)');
            ws.send(Buffer.from([1]));
            handshakeStep = 3;
        } else {
            console.log('Security handshake failed');
        }
        
    } else if (handshakeStep === 3) {
        // ServerInit
        console.log('ServerInit received');
        const width = data.readUInt16BE(0);
        const height = data.readUInt16BE(2);
        console.log(`Framebuffer size: ${width}x${height}`);
        
        // Parse pixel format (16 bytes starting at offset 4)
        const pixelFormat = data.slice(4, 20);
        console.log('Pixel format:', pixelFormat);
        
        // Parse name length and name
        const nameLength = data.readUInt32BE(20);
        const name = data.slice(24, 24 + nameLength).toString();
        console.log(`Desktop name: "${name}"`);
        
        console.log('VNC handshake complete!');
        handshakeStep = 4;
        
        // Request screen update
        setTimeout(() => {
            console.log('Requesting framebuffer update...');
            // FramebufferUpdateRequest: type(3) + incremental(0) + x(0) + y(0) + width + height
            const updateRequest = Buffer.alloc(10);
            updateRequest[0] = 3; // FramebufferUpdateRequest
            updateRequest[1] = 0; // incremental = 0 (full update)
            updateRequest.writeUInt16BE(0, 2); // x
            updateRequest.writeUInt16BE(0, 4); // y
            updateRequest.writeUInt16BE(width, 6); // width
            updateRequest.writeUInt16BE(height, 8); // height
            ws.send(updateRequest);
        }, 1000);
        
    } else {
        // Framebuffer updates
        console.log(`Framebuffer data received: ${data.length} bytes`);
        if (data.length > 0) {
            console.log('First few bytes:', data.slice(0, Math.min(20, data.length)));
        }
    }
});

ws.on('error', (err) => {
    console.error('WebSocket error:', err);
});

ws.on('close', (code, reason) => {
    console.log('WebSocket closed:', code, reason?.toString());
});

// Keep the process alive
setTimeout(() => {
    console.log('Test timeout - closing connection');
    ws.close();
}, 30000);
