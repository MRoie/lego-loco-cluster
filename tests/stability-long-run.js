#!/usr/bin/env node

const WebSocket = require('ws');
const { createTestLogger } = require('../utils/logger');

const DURATION_SECONDS = process.env.DURATION ? parseInt(process.env.DURATION) : 360; // Default 6 minutes
const INSTANCE_URL = process.env.VNC_URL || 'ws://localhost:3000/proxy/vnc/instance-0/';
const logger = createTestLogger('stability-long-run');

logger.info('Starting Long-Running VNC Stability Test', {
    durationMatches: `${DURATION_SECONDS}s`,
    target: INSTANCE_URL
});

const ws = new WebSocket(INSTANCE_URL);
let handshakeStep = 0;
let width = 0;
let height = 0;
let updateInterval = null;
let startTime = Date.now();

ws.on('open', () => {
    logger.info('WebSocket connected');
});

ws.on('message', (data) => {
    // Handle Handshake
    if (handshakeStep === 0) {
        // Version
        ws.send('RFB 003.008\n');
        handshakeStep = 1;
    } else if (handshakeStep === 1) {
        // Security Types
        // Select None (1)
        ws.send(Buffer.from([1]));
        handshakeStep = 2;
    } else if (handshakeStep === 2) {
        // Security Result
        const result = data.readUInt32BE(0);
        if (result === 0) {
            logger.info('Security Handshake OK');
            // ClientInit (Shared=1)
            ws.send(Buffer.from([1]));
            handshakeStep = 3;
        } else {
            logger.error('Security Handshake Failed', { result });
            process.exit(1);
        }
    } else if (handshakeStep === 3) {
        // ServerInit
        width = data.readUInt16BE(0);
        height = data.readUInt16BE(2);
        const nameLen = data.readUInt32BE(20);
        const name = data.slice(24, 24 + nameLen).toString();
        logger.info('VNC Session Established', { width, height, name });
        handshakeStep = 4;

        // Start Keepalive / Activity Loop
        startActivityLoop();
    } else {
        // Framebuffer Updates
        // Just consume them
    }
});

function startActivityLoop() {
    logger.info(`Starting activity loop for ${DURATION_SECONDS} seconds`);

    updateInterval = setInterval(() => {
        const elapsed = (Date.now() - startTime) / 1000;

        if (elapsed >= DURATION_SECONDS) {
            logger.info('Test Duration Reached - SUCCESS');
            clearInterval(updateInterval);
            ws.close();
            process.exit(0);
        }

        if (ws.readyState === WebSocket.OPEN) {
            logger.info(`Connection healthy... (${Math.round(elapsed)}s / ${DURATION_SECONDS}s)`);

            // Send FramebufferUpdateRequest (Full) to simulate activity
            const req = Buffer.alloc(10);
            req[0] = 3; // MessageType: FramebufferUpdateRequest
            req[1] = 0; // Incremental: 0 (Full)
            req.writeUInt16BE(0, 2); // x
            req.writeUInt16BE(0, 4); // y
            req.writeUInt16BE(width, 6); // w
            req.writeUInt16BE(height, 8); // h
            ws.send(req);
        } else {
            logger.error('WebSocket not open during loop', { state: ws.readyState });
            process.exit(1);
        }
    }, 5000); // Check every 5 seconds
}

ws.on('close', (code, reason) => {
    const elapsed = (Date.now() - startTime) / 1000;
    if (elapsed < DURATION_SECONDS) {
        logger.error('Connection Closed Prematurely!', { code, reason: reason?.toString(), elapsed });
        process.exit(1);
    } else {
        logger.info('Connection closed naturally after test completion');
    }
});

ws.on('error', (err) => {
    logger.error('WebSocket Error', { error: err.message });
    process.exit(1);
});
