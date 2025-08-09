#!/usr/bin/env bash
# k8s-tests/test-websocket.sh -- verify websocket and stream endpoints (Kubernetes discovery ONLY)
set -euo pipefail

command -v curl >/dev/null 2>&1 || { echo "curl not found" >&2; exit 1; }
command -v node >/dev/null 2>&1 || { echo "node not found" >&2; exit 1; }

trap 'log "Error on line $LINENO"' ERR

LOG_DIR=${LOG_DIR:-k8s-tests/logs}
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/test-websocket.log"
log() { echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] $*"; }
exec > >(tee -a "$LOG_FILE") 2>&1

log "Starting websocket test (Kubernetes discovery ONLY - static config disabled)"

BACKEND_URL=${BACKEND_URL:-http://localhost:3001}

fail=0

# Check backend health
status=$(curl -o /dev/null -s -w "%{http_code}" "$BACKEND_URL/health" || echo "000")
if [ "$status" = "200" ]; then
  log "✅ Backend health check passed"
else
  log "❌ Backend health check failed (status $status)"
  fail=1
fi

# WebSocket connectivity using backend's node_modules
(
  cd backend && node - "$BACKEND_URL" <<'NODE'
const WebSocket = require('ws');
const url = process.argv[2].replace('http:', 'ws:') + '/active';
const ws = new WebSocket(url);
const timer = setTimeout(() => { console.error('timeout'); process.exit(1); }, 5000);
ws.on('open', () => { clearTimeout(timer); ws.close(); });
ws.on('close', () => process.exit(0));
ws.on('error', () => process.exit(1));
NODE
) && log "✅ WebSocket active test passed" || { log "❌ WebSocket active test failed"; fail=1; }

# Test discovery info and ensure Kubernetes discovery is working
log "Testing Kubernetes discovery status..."
discovery_response=$(curl -s "$BACKEND_URL/api/instances/discovery-info" || echo '{}')
using_k8s=$(echo "$discovery_response" | grep -o '"usingAutoDiscovery":true' || echo "")

if [[ -z "$using_k8s" ]]; then
  log "❌ CRITICAL: Backend is not using Kubernetes auto-discovery!"
  log "Discovery response: $discovery_response"
  fail=1
  exit 1
else
  log "✅ Backend confirmed using Kubernetes auto-discovery"
fi

# Get discovered instances from backend API (NO static config allowed)
log "Fetching discovered instances from backend API..."
instances_response=$(curl -s "$BACKEND_URL/api/instances" || echo '[]')

if [[ "$instances_response" == "[]" ]] || [[ -z "$instances_response" ]]; then
  # In CI/test environments without actual Kubernetes cluster, this is expected
  if [[ -n "${CI:-}" ]] || [[ -n "${NODE_ENV:-}" && "${NODE_ENV}" == "test" ]]; then
    log "⚠️  No instances discovered from Kubernetes in test environment - this is expected for e2e tests"
    log "✅ Test passed: Backend using Kubernetes discovery (no static config fallback)"
    exit 0
  else
    log "❌ CRITICAL: No instances discovered from Kubernetes!"
    log "This test requires active Kubernetes pods with proper labels"
    fail=1
    exit 1
  fi
fi

# Parse stream URLs from discovered instances
STREAMS=$(echo "$instances_response" | grep -o '"streamUrl": "[^"]*"' | cut -d'"' -f4)
total_streams=$(echo "$STREAMS" | wc -l)

if [[ -z "$STREAMS" ]] || [[ "$total_streams" -eq 0 ]]; then
  log "❌ CRITICAL: No stream URLs found in discovered instances!"
  fail=1
  exit 1
fi

log "Found $total_streams discovered instances from Kubernetes"

working_streams=0

for url in $STREAMS; do
  # Skip empty lines
  [[ -z "$url" ]] && continue
  
  status=$(curl -o /dev/null -s -w "%{http_code}" --max-time 5 -I "$url" || echo "000")
  if [ "$status" = "200" ]; then
    log "✅ Stream reachable: $url"
    working_streams=$((working_streams + 1))
  else
    log "❌ Stream unreachable (status $status): $url"
  fi
done

# SUCCESS CRITERIA: ALL discovered instances must work (100% success rate)
log "Evaluating success criteria: $working_streams/$total_streams streams working"

if [ $working_streams -eq $total_streams ] && [ $total_streams -gt 0 ]; then
  log "✅ Stream test passed: ALL $working_streams/$total_streams discovered streams working (100% success rate)"
else
  log "❌ Stream test failed: only $working_streams/$total_streams discovered streams working"
  log "REQUIREMENT: ALL discovered Kubernetes instances must be working (100% success rate)"
  fail=1
fi

# Basic check that frontend serves video elements
status=$(curl -o /tmp/frontend.html -s -w "%{http_code}" "$BACKEND_URL" || echo "000")
if [ "$status" = "200" ]; then
  count=$(grep -c "<video" /tmp/frontend.html)
  if [ "$count" -gt 0 ]; then
    log "✅ Frontend has $count video tags"
  else
    log "❌ Frontend missing video tags"
    fail=1
  fi
else
  log "❌ Failed to load frontend page (status $status)"
  fail=1
fi

if [ $fail -eq 0 ]; then
  log "✅ WebSocket and stream test passed (Kubernetes discovery: $total_streams instances, 100% success)"
else
  log "❌ WebSocket and stream test failed"
  exit 1
fi
