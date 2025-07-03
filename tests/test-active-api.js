#!/usr/bin/env node
const http = require('http');

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
  req.write(JSON.stringify({id}));
  req.end();
}

getActive((err, orig) => {
  if (err) return console.error('Failed to get active', err);
  console.log('Current active:', orig);
  const testId = 'instance-1';
  setActive(testId, () => {
    getActive((err2, id) => {
      if (err2) return console.error('Failed to read active after set', err2);
      console.log('Updated active:', id);
      if (id !== testId) {
        console.error('❌ Active ID mismatch');
        process.exit(1);
      } else {
        // restore original
        if (orig && orig !== testId) setActive(orig, () => process.exit(0));
        else process.exit(0);
      }
    });
  });
});
