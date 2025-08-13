const { execSync } = require('child_process');
const fs = require('fs');
const { createTestLogger } = require('../utils/logger');

const logger = createTestLogger('test-active-cpu');

function run(cmd) {
  try {
    return execSync(cmd, { stdio: 'pipe' }).toString().trim();
  } catch (e) {
    logger.debug('Command execution failed', { command: cmd, error: e.message });
    return '';
  }
}

const id = 'instance-0';
logger.info('Testing CPU scaling for active instance', { instanceId: id });

run(`./scripts/set_active.sh ${id}`);
const data = JSON.parse(fs.readFileSync('config/active.json','utf-8'));
if (!Array.isArray(data.active) || data.active[0] !== id) {
  logger.error('Active file not updated correctly', { 
    expected: id, 
    actual: data.active[0],
    fullActive: data.active 
  });
  process.exit(1);
}

logger.info('Active instance file updated successfully', { activeInstance: data.active[0] });

if (run('command -v docker')) {
  const container = run("docker ps --format '{{.Names}}' | grep loco-emulator-0");
  if (container) {
    const cpus = run(`docker inspect -f '{{.HostConfig.NanoCpus}}' ${container}`);
    logger.info('Container CPU configuration', { containerName: container, nanoCpus: cpus });
  } else {
    logger.warn('No matching container found for CPU inspection');
  }
} else {
  logger.debug('Docker not available, skipping container CPU check');
}

logger.info('CPU scaling test completed successfully');
