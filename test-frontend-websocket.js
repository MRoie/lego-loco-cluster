#!/usr/bin/env node

const WebSocket = require('ws');

console.log('Testing WebSocket connection through frontend proxy...');

// Test connection through frontend proxy
const ws = new WebSocket('ws://localhost:3000/proxy/vnc/instance-0/');

ws.on('open', () => {
    console.log('✅ WebSocket connected through frontend proxy!');
});

ws.on('message', (data) => {
    console.log('📨 Received data:', data.length, 'bytes');
    console.log('First 20 bytes:', data.slice(0, 20));
});

ws.on('error', (err) => {
    console.error('❌ WebSocket error:', err.message);
});

ws.on('close', (code, reason) => {
    console.log('🔌 WebSocket closed:', code, reason?.toString());
    process.exit(0);
});

// Timeout after 10 seconds
setTimeout(() => {
    console.log('⏰ Timeout - closing connection');
    ws.close();
}, 10000);
