#!/usr/bin/env node
const http = require('http');
const { createTestLogger } = require('../utils/logger');

const logger = createTestLogger('test-active-api');

function getActive(cb) {
  http.get('http://localhost:3001/api/active', (res) => {
    let data='';
    res.on('data', c => data+=c);
    res.on('end', () => {
      try { cb(null, JSON.parse(data).active); } catch(e){ cb(e); }
    });
  }).on('error', cb);
}

function setActive(id, cb) {
  const req = http.request('http://localhost:3001/api/active', {method:'POST', headers:{'Content-Type':'application/json'}}, res => {
    res.resume(); res.on('end', () => cb());
  });
  req.write(JSON.stringify({ids:[id]}));
  req.end();
}

getActive((err, orig) => {
  if (err) {
    logger.error('Failed to get active instances', { error: err.message });
    return;
  }
  logger.info('Current active instances', { activeInstances: orig });
  const testId = 'instance-1';
  setActive(testId, () => {
    getActive((err2, ids) => {
      if (err2) {
        logger.error('Failed to read active after set', { testId, error: err2.message });
        return;
      }
      logger.info('Updated active instances', { activeInstances: ids });
      if (!Array.isArray(ids) || ids[0] !== testId) {
        logger.error('Active ID mismatch - test failed', { 
          expected: testId, 
          actual: ids[0],
          fullIds: ids 
        });
        process.exit(1);
      } else {
        logger.info('Active API test passed successfully');
        // restore original
        if (orig && orig[0] !== testId) {
          logger.debug('Restoring original active instance', { originalId: orig[0] });
          setActive(orig[0], () => process.exit(0));
        } else {
          process.exit(0);
        }
      }
    });
  });
});
