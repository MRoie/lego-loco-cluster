#!/usr/bin/env node

const WebSocket = require('ws');
const { createTestLogger } = require('../utils/logger');

const logger = createTestLogger('test-vnc-connection');

logger.info('Starting VNC WebSocket connection test');

// Connect to the VNC proxy
const ws = new WebSocket('ws://localhost:3001/proxy/vnc/instance-0/');

let handshakeStep = 0;

ws.on('open', () => {
    logger.info('WebSocket connected successfully');
});

ws.on('message', (data) => {
    logger.debug('VNC handshake step', { step: handshakeStep, dataLength: data.length });
    
    if (handshakeStep === 0) {
        // VNC server version - respond with client version
        const serverVersion = data.toString();
        logger.info('Received server version', { serverVersion: JSON.stringify(serverVersion) });
        
        const clientVersion = 'RFB 003.008\n';
        logger.info('Sending client version', { clientVersion: JSON.stringify(clientVersion) });
        ws.send(clientVersion);
        handshakeStep = 1;
        
    } else if (handshakeStep === 1) {
        // Security types
        logger.debug('Security types received');
        const numTypes = data[0];
        logger.info('Security types available', { numTypes });
        
        if (numTypes > 0) {
            const securityTypes = [];
            for (let i = 0; i < numTypes; i++) {
                const securityType = data[1 + i];
                securityTypes.push(securityType);
                logger.debug('Security type discovered', { index: i, type: securityType });
            }
            
            // Select "None" security (type 1)
            logger.info('Selecting security type', { selectedType: 1, description: 'None' });
            ws.send(Buffer.from([1]));
            handshakeStep = 2;
        }
        
    } else if (handshakeStep === 2) {
        // Security result
        const result = data.readUInt32BE(0);
        logger.info('Security handshake result', { result });
        
        if (result === 0) {
            logger.info('Security handshake successful');
            logger.debug('Sending ClientInit', { shared: true });
            ws.send(Buffer.from([1]));
            handshakeStep = 3;
        } else {
            logger.error('Security handshake failed', { result });
        }
        
    } else if (handshakeStep === 3) {
        // ServerInit
        logger.info('ServerInit received');
        const width = data.readUInt16BE(0);
        const height = data.readUInt16BE(2);
        logger.info('Framebuffer configuration', { width, height });
        
        // Parse pixel format (16 bytes starting at offset 4)
        const pixelFormat = data.slice(4, 20);
        logger.debug('Pixel format received', { pixelFormat: pixelFormat.toString('hex') });
        
        // Parse name length and name
        const nameLength = data.readUInt32BE(20);
        const name = data.slice(24, 24 + nameLength).toString();
        logger.info('Desktop configuration', { desktopName: name });
        
        logger.info('VNC handshake completed successfully');
        handshakeStep = 4;
        
        // Request screen update
        setTimeout(() => {
            logger.debug('Requesting framebuffer update');
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
        logger.debug('Framebuffer data received', { dataLength: data.length });
        if (data.length > 0) {
            const preview = data.slice(0, Math.min(20, data.length));
            logger.debug('Framebuffer data preview', { preview: preview.toString('hex') });
        }
    }
});

ws.on('error', (err) => {
    logger.error('WebSocket error occurred', { error: err.message });
});

ws.on('close', (code, reason) => {
    logger.info('WebSocket connection closed', { code, reason: reason?.toString() });
});

// Keep the process alive
setTimeout(() => {
    console.log('Test timeout - closing connection');
    ws.close();
}, 30000);
