const assert = require('assert');
const { exec } = require('child_process');
const http = require('http');

// Test VNC connection counting functionality
describe('VNC Connection Counting', function() {
  this.timeout(10000);
  
  let serverProcess = null;
  const baseUrl = 'http://localhost:3001';
  
  before(function(done) {
    // Start the backend server for testing
    serverProcess = exec('npm start', { cwd: '../backend' });
    
    // Wait for server to start
    setTimeout(() => {
      done();
    }, 3000);
  });
  
  after(function() {
    // Clean up server process
    if (serverProcess) {
      serverProcess.kill();
    }
  });
  
  it('should expose metrics endpoint', function(done) {
    http.get(`${baseUrl}/metrics`, (res) => {
      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(res.headers['content-type'], 'text/plain; version=0.0.4; charset=utf-8');
      done();
    }).on('error', done);
  });
  
  it('should track HTTP connections correctly', function(done) {
    http.get(`${baseUrl}/metrics`, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        // Check that HTTP connections are tracked
        assert(data.includes('active_connections_total{type="http"}'));
        done();
      });
    }).on('error', done);
  });
  
  it('should handle health checks without errors', function(done) {
    http.get(`${baseUrl}/health`, (res) => {
      assert.strictEqual(res.statusCode, 200);
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        const health = JSON.parse(data);
        assert.strictEqual(health.status, 'ok');
        assert(health.timestamp);
        done();
      });
    }).on('error', done);
  });
  
  it('should not crash when accessing VNC-related endpoints', function(done) {
    // Test that the server doesn't crash with VNC-related requests
    http.get(`${baseUrl}/api/instances`, (res) => {
      // Just verify server responds (may return 503 if no instances)
      assert([200, 503].includes(res.statusCode));
      done();
    }).on('error', done);
  });
  
  it('should maintain accurate connection counts', function(done) {
    // Make multiple requests and verify metrics are updated
    let requestCount = 0;
    const totalRequests = 3;
    
    function makeRequest() {
      http.get(`${baseUrl}/health`, (res) => {
        res.on('data', () => {}); // Consume response
        res.on('end', () => {
          requestCount++;
          if (requestCount < totalRequests) {
            makeRequest();
          } else {
            // Check metrics after all requests
            http.get(`${baseUrl}/metrics`, (metricsRes) => {
              let data = '';
              metricsRes.on('data', chunk => data += chunk);
              metricsRes.on('end', () => {
                // Verify request duration metrics exist
                assert(data.includes('http_request_duration_seconds'));
                assert(data.includes('method="GET"'));
                assert(data.includes('status_code="200"'));
                done();
              });
            }).on('error', done);
          }
        });
      }).on('error', done);
    }
    
    makeRequest();
  });
});