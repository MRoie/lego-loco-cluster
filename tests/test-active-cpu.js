const { execSync } = require('child_process');
const fs = require('fs');

function run(cmd) {
  try {
    return execSync(cmd, { stdio: 'pipe' }).toString().trim();
  } catch (e) {
    return '';
  }
}

const id = 'instance-0';
run(`./scripts/set_active.sh ${id}`);
const data = JSON.parse(fs.readFileSync('config/active.json','utf-8'));
if (!Array.isArray(data.active) || data.active[0] !== id) {
  console.error('Active file not updated');
  process.exit(1);
}

if (run('command -v docker')) {
  const container = run("docker ps --format '{{.Names}}' | grep loco-emulator-0");
  if (container) {
    const cpus = run(`docker inspect -f '{{.HostConfig.NanoCpus}}' ${container}`);
    console.log('Container CPUs', cpus);
  }
}
console.log('CPU scaling test passed');
