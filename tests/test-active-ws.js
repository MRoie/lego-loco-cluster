#!/usr/bin/env node
const WebSocket = require('../backend/node_modules/ws');
const http = require('http');

const ws = new WebSocket('ws://localhost:3001/active');
ws.on('message', msg => {
  const data = JSON.parse(msg);
  console.log('WS update', data.active);
  ws.close();
  process.exit(0);
});
ws.on('open', () => {
  const req = http.request('http://localhost:3001/api/active', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' }
  });
  req.write(JSON.stringify({ id: 'instance-2' }));
  req.end();
});
ws.on('error', err => {
  console.error('WebSocket error', err.message);
  process.exit(1);
});
