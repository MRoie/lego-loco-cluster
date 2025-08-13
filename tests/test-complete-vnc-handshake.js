#!/usr/bin/env node

const WebSocket = require('ws');
const { createTestLogger } = require('../utils/logger');

const logger = createTestLogger('test-complete-vnc-handshake');

logger.info('Starting complete VNC handshake test through frontend proxy');

// Connect to VNC through frontend proxy
const ws = new WebSocket('ws://localhost:3000/proxy/vnc/instance-0/');
ws.binaryType = 'arraybuffer';

let handshakeStep = 0;

ws.on('open', () => {
    logger.info('WebSocket connected successfully');
});

ws.on('message', (data) => {
    const bytes = new Uint8Array(data);
    logger.debug('VNC handshake step', { step: handshakeStep, dataLength: bytes.length });
    
    if (handshakeStep === 0) {
        // VNC server version
        const serverVersion = new TextDecoder().decode(bytes.slice(0, 12));
        logger.info('Server version received', { serverVersion: JSON.stringify(serverVersion) });
        
        // Send client version
        const clientVersion = 'RFB 003.008\n';
        logger.info('Sending client version', { clientVersion: JSON.stringify(clientVersion) });
        ws.send(new TextEncoder().encode(clientVersion));
        handshakeStep = 1;
        
    } else if (handshakeStep === 1) {
        // Security types
        const numTypes = bytes[0];
        console.log(`🔒 Security types available: ${numTypes}`);
        
        for (let i = 0; i < numTypes; i++) {
            console.log(`   Type ${i}: ${bytes[1 + i]}`);
        }
        
        // Select None security (type 1)
        console.log(`📤 Selecting None security (type 1)`);
        ws.send(new Uint8Array([1]));
        handshakeStep = 2;
        
    } else if (handshakeStep === 2) {
        // Security result
        const view = new DataView(data);
        const result = view.getUint32(0, false); // big-endian
        console.log(`🔓 Security result: ${result}`);
        
        if (result === 0) {
            console.log(`✅ Security handshake successful`);
            console.log(`📤 Sending ClientInit (shared=1)`);
            ws.send(new Uint8Array([1]));
            handshakeStep = 3;
        } else {
            console.log(`❌ Security handshake failed`);
        }
        
    } else if (handshakeStep === 3) {
        // ServerInit
        const view = new DataView(data);
        const width = view.getUint16(0, false);
        const height = view.getUint16(2, false);
        const nameLength = view.getUint32(20, false);
        const name = new TextDecoder().decode(bytes.slice(24, 24 + nameLength));
        
        console.log(`🖥️  Framebuffer: ${width}x${height}`);
        console.log(`📛 Desktop name: "${name}"`);
        console.log(`🎉 VNC handshake complete!`);
        
        // Request framebuffer update
        console.log(`📤 Requesting framebuffer update...`);
        const updateRequest = new ArrayBuffer(10);
        const reqView = new DataView(updateRequest);
        reqView.setUint8(0, 3); // FramebufferUpdateRequest
        reqView.setUint8(1, 0); // incremental = 0 (full update)
        reqView.setUint16(2, 0, false); // x
        reqView.setUint16(4, 0, false); // y
        reqView.setUint16(6, width, false); // width
        reqView.setUint16(8, height, false); // height
        ws.send(updateRequest);
        handshakeStep = 4;
        
    } else {
        // Framebuffer updates
        console.log(`🖼️  Framebuffer data: ${bytes.length} bytes`);
        if (bytes.length > 0) {
            console.log(`   First few bytes: ${Array.from(bytes.slice(0, 10)).map(b => b.toString(16).padStart(2, '0')).join(' ')}`);
        }
    }
});

ws.on('error', (err) => {
    console.error('❌ WebSocket error:', err.message);
});

ws.on('close', (code, reason) => {
    console.log(`🔌 WebSocket closed: ${code} ${reason?.toString()}`);
    process.exit(0);
});

// Timeout after 15 seconds
setTimeout(() => {
    console.log('⏰ Test timeout - closing connection');
    ws.close();
}, 15000);
