#!/usr/bin/env node

const WebSocket = require('ws');
const { createTestLogger } = require('../utils/logger');

const logger = createTestLogger('test-frontend-websocket');

logger.info('Starting WebSocket connection test through frontend proxy');

// Test connection through frontend proxy
const ws = new WebSocket('ws://localhost:3000/proxy/vnc/instance-0/');

ws.on('open', () => {
    logger.info('WebSocket connected through frontend proxy successfully');
});

ws.on('message', (data) => {
    logger.debug('Received data from WebSocket', { 
      dataLength: data.length,
      preview: data.slice(0, 20).toString('hex')
    });
});

ws.on('error', (err) => {
    logger.error('WebSocket error occurred', { error: err.message });
});

ws.on('close', (code, reason) => {
    logger.info('WebSocket connection closed', { 
      code, 
      reason: reason?.toString() 
    });
    process.exit(0);
});

// Timeout after 10 seconds
setTimeout(() => {
    logger.info('Test timeout reached, closing connection');
    ws.close();
}, 10000);
