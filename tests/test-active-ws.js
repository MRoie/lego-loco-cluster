#!/usr/bin/env node
const WebSocket = require('ws');
const http = require('http');
const { createTestLogger } = require('../utils/logger');

const logger = createTestLogger('test-active-ws');

const ws = new WebSocket('ws://localhost:3001/active');
ws.on('message', msg => {
  const data = JSON.parse(msg);
  logger.info('WebSocket update received', { activeInstances: data.active });
  ws.close();
  if (Array.isArray(data.active)) {
    logger.info('Active WebSocket test passed successfully');
    process.exit(0);
  } else {
    logger.error('Active data is not an array', { received: data.active });
    process.exit(1);
  }
});
ws.on('open', () => {
  logger.info('WebSocket connected, triggering active instance change');
  const req = http.request('http://localhost:3001/api/active', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' }
  });
  req.write(JSON.stringify({ ids: ['instance-2'] }));
  req.end();
});
ws.on('error', err => {
  logger.error('WebSocket error occurred', { error: err.message });
  process.exit(1);
});
