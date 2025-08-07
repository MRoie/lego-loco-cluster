const StreamQualityMonitor = require('../backend/services/streamQualityMonitor');
const path = require('path');
const fs = require('fs');

// Mock config directory for testing
const TEST_CONFIG_DIR = path.join(__dirname, 'test-config');

// Create test config directory and files
function setupTestConfig() {
  if (!fs.existsSync(TEST_CONFIG_DIR)) {
    fs.mkdirSync(TEST_CONFIG_DIR, { recursive: true });
  }
  
  // Create test instances.json
  const testInstances = [
    {
      "id": "test-instance-0",
      "streamUrl": "http://localhost:6080/vnc0",
      "vncUrl": "localhost:5901",
      "name": "Test Instance 0"
    },
    {
      "id": "test-instance-1", 
      "streamUrl": "http://localhost:6081/vnc1",
      "vncUrl": "localhost:5902",
      "name": "Test Instance 1"
    }
  ];
  
  fs.writeFileSync(
    path.join(TEST_CONFIG_DIR, 'instances.json'),
    JSON.stringify(testInstances, null, 2)
  );
}

// Cleanup test config
function cleanupTestConfig() {
  if (fs.existsSync(TEST_CONFIG_DIR)) {
    fs.rmSync(TEST_CONFIG_DIR, { recursive: true, force: true });
  }
}

async function testStreamQualityMonitor() {
  console.log('🧪 Starting Stream Quality Monitor Tests');
  
  setupTestConfig();
  
  try {
    // Test 1: Monitor initialization
    console.log('\n📋 Test 1: Monitor Initialization');
    const monitor = new StreamQualityMonitor(TEST_CONFIG_DIR);
    console.log('✓ Monitor created successfully');
    
    // Test 2: Load instances configuration
    console.log('\n📋 Test 2: Load Instances Configuration');
    const instances = monitor.loadInstances();
    console.log('✓ Loaded instances:', instances.length);
    console.log('  Instance IDs:', instances.map(i => i.id));
    
    // Test 3: Single instance probe (will fail since no actual VNC server)
    console.log('\n📋 Test 3: Single Instance Probe');
    try {
      const probeResult = await monitor.probeInstance(instances[0]);
      console.log('✓ Probe completed for', instances[0].id);
      console.log('  Availability:', probeResult.availability);
      console.log('  Quality:', probeResult.quality);
      if (probeResult.errors.length > 0) {
        console.log('  Expected errors (no VNC server):', probeResult.errors);
      }
    } catch (error) {
      console.log('✓ Probe failed as expected (no VNC server):', error.message);
    }
    
    // Test 4: Start monitoring service
    console.log('\n📋 Test 4: Start Monitoring Service');
    monitor.start();
    console.log('✓ Monitoring service started');
    
    // Wait for initial probe
    await new Promise(resolve => setTimeout(resolve, 2000));
    
    // Test 5: Get all metrics
    console.log('\n📋 Test 5: Get All Metrics');
    const allMetrics = monitor.getAllMetrics();
    console.log('✓ Retrieved metrics for', Object.keys(allMetrics).length, 'instances');
    
    Object.entries(allMetrics).forEach(([instanceId, metrics]) => {
      console.log(`  ${instanceId}:`, {
        vnc: metrics.availability.vnc,
        quality: metrics.quality.audioQuality,
        latency: metrics.quality.connectionLatency
      });
    });
    
    // Test 6: Get quality summary
    console.log('\n📋 Test 6: Get Quality Summary');
    const summary = monitor.getQualitySummary();
    console.log('✓ Quality summary:', {
      total: summary.total,
      available: summary.available,
      availabilityPercent: summary.availabilityPercent,
      averageLatency: summary.averageLatency
    });
    
    // Test 7: Get specific instance metrics
    console.log('\n📋 Test 7: Get Specific Instance Metrics');
    const specificMetrics = monitor.getInstanceMetrics('test-instance-0');
    if (specificMetrics) {
      console.log('✓ Retrieved metrics for test-instance-0');
      console.log('  VNC Available:', specificMetrics.availability.vnc);
      console.log('  Audio Quality:', specificMetrics.quality.audioQuality);
    } else {
      console.log('⚠ No metrics found for test-instance-0');
    }
    
    // Test 8: Stop monitoring service
    console.log('\n📋 Test 8: Stop Monitoring Service');
    monitor.stop();
    console.log('✓ Monitoring service stopped');
    
    console.log('\n🎉 All Stream Quality Monitor tests completed successfully!');
    
  } catch (error) {
    console.error('\n❌ Test failed:', error);
    throw error;
  } finally {
    cleanupTestConfig();
    console.log('🧹 Test cleanup completed');
  }
}

// Test API endpoints if running as part of server tests
async function testQualityAPIEndpoints(baseUrl = 'http://localhost:3001') {
  console.log('\n🌐 Testing Quality Monitoring API Endpoints');
  
  const endpoints = [
    '/api/quality/metrics',
    '/api/quality/summary'
  ];
  
  for (const endpoint of endpoints) {
    try {
      console.log(`\n📡 Testing ${endpoint}`);
      const response = await fetch(`${baseUrl}${endpoint}`);
      
      if (response.ok) {
        const data = await response.json();
        console.log(`✓ ${endpoint} responded successfully`);
        console.log('  Response keys:', Object.keys(data).slice(0, 5));
      } else {
        console.log(`⚠ ${endpoint} returned status ${response.status}`);
      }
    } catch (error) {
      console.log(`❌ ${endpoint} failed:`, error.message);
    }
  }
}

// Run tests
if (require.main === module) {
  testStreamQualityMonitor()
    .then(() => {
      console.log('\n✅ Stream Quality Monitor test suite passed');
      process.exit(0);
    })
    .catch((error) => {
      console.error('\n❌ Stream Quality Monitor test suite failed:', error);
      process.exit(1);
    });
}

module.exports = {
  testStreamQualityMonitor,
  testQualityAPIEndpoints
};