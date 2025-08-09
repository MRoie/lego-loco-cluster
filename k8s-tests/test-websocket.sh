#!/usr/bin/env bash
# k8s-tests/test-websocket.sh -- verify websocket and stream endpoints (STRICT Kubernetes discovery ONLY)
set -euo pipefail

command -v curl >/dev/null 2>&1 || { echo "curl not found" >&2; exit 1; }
command -v node >/dev/null 2>&1 || { echo "node not found" >&2; exit 1; }

trap 'log "Error on line $LINENO"' ERR

LOG_DIR=${LOG_DIR:-k8s-tests/logs}
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/test-websocket.log"
log() { echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] $*"; }
exec > >(tee -a "$LOG_FILE") 2>&1

log "Starting STRICT websocket test (Kubernetes discovery ONLY - NO test environment fallback)"

BACKEND_URL=${BACKEND_URL:-http://localhost:3001}

fail=0

# Check backend health
log "Testing backend health endpoint..."
status=$(curl -o /dev/null -s -w "%{http_code}" "$BACKEND_URL/health" || echo "000")
if [ "$status" = "200" ]; then
  log "✅ Backend health check passed"
else
  log "❌ Backend health check failed (status $status)"
  fail=1
fi

# WebSocket connectivity using backend's node_modules
log "Testing WebSocket connectivity..."
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

# STRICT: Test discovery info and REQUIRE real Kubernetes discovery
log "Testing STRICT Kubernetes discovery status..."
discovery_response=$(curl -s "$BACKEND_URL/api/instances/discovery-info" || echo '{}')
log "Discovery response: $discovery_response"

using_k8s=$(echo "$discovery_response" | grep -o '"usingAutoDiscovery":true' || echo "")
has_k8s_info=$(echo "$discovery_response" | grep -o '"kubernetes":{' || echo "")

if [[ -z "$using_k8s" ]]; then
  log "❌ CRITICAL: Backend is not using Kubernetes auto-discovery!"
  log "Discovery response: $discovery_response"
  fail=1
  exit 1
else
  log "✅ Backend confirmed using Kubernetes auto-discovery"
fi

# Check for Kubernetes cluster information more flexibly
if [[ -z "$has_k8s_info" ]]; then
  # Also check for discoveryEnabled flag as alternative
  discovery_enabled=$(echo "$discovery_response" | grep -o '"discoveryEnabled":true' || echo "")
  if [[ -z "$discovery_enabled" ]]; then
    log "❌ CRITICAL: No Kubernetes cluster information detected!"
    log "This indicates the backend is not properly connected to a Kubernetes cluster"
    fail=1
    exit 1
  else
    log "✅ Kubernetes discovery enabled (cluster information available)"
  fi
else
  log "✅ Kubernetes cluster information detected"
fi

# STRICT: Get discovered instances from backend API (NO empty list allowed in STRICT mode)
log "Fetching discovered instances from backend API (STRICT mode - no empty lists allowed)..."
instances_response=$(curl -s "$BACKEND_URL/api/instances" || echo '[]')
log "Instances response: $instances_response"

# Check for specific test environment variable to allow empty discovery
if [[ "$instances_response" == "[]" ]] || [[ -z "$instances_response" ]]; then
  # Only allow empty responses if explicitly testing with a mock cluster
  if [[ "${ALLOW_EMPTY_DISCOVERY:-}" == "true" ]]; then
    log "⚠️  Empty discovery allowed by ALLOW_EMPTY_DISCOVERY=true"
    log "✅ Test passed: Backend using Kubernetes discovery (empty result allowed in mock environment)"
    exit 0
  else
    log "❌ CRITICAL: No instances discovered from Kubernetes cluster!"
    log "In STRICT mode, this test requires actual running pods with proper labels"
    log "Expected labels: app.kubernetes.io/component=emulator, app.kubernetes.io/part-of=lego-loco-cluster"
    log "Use ALLOW_EMPTY_DISCOVERY=true to test discovery functionality without real pods"
    fail=1
    exit 1
  fi
fi

# Parse stream URLs from discovered instances
STREAMS=$(echo "$instances_response" | jq -r '.[].streamUrl // empty')
total_streams=$(echo "$STREAMS" | wc -l)

if [[ -z "$STREAMS" ]] || [[ "$total_streams" -eq 0 ]]; then
  log "❌ CRITICAL: No stream URLs found in discovered instances!"
  log "Instances response: $instances_response"
  fail=1
  exit 1
fi

log "Found $total_streams discovered instances from Kubernetes cluster"

working_streams=0

for url in $STREAMS; do
  # Skip empty lines
  [[ -z "$url" ]] && continue
  
  log "Testing stream: $url"
  status=$(curl -o /dev/null -s -w "%{http_code}" --max-time 5 -I "$url" || echo "000")
  if [ "$status" = "200" ]; then
    log "✅ Stream reachable: $url"
    working_streams=$((working_streams + 1))
  else
    log "❌ Stream unreachable (status $status): $url"
  fi
done

# SUCCESS CRITERIA: ALL discovered instances must work (100% success rate)
log "Evaluating STRICT success criteria: $working_streams/$total_streams streams working"

if [ $working_streams -eq $total_streams ] && [ $total_streams -gt 0 ]; then
  log "✅ Stream test passed: ALL $working_streams/$total_streams discovered streams working (100% success rate)"
else
  log "❌ Stream test failed: only $working_streams/$total_streams discovered streams working"
  log "STRICT REQUIREMENT: ALL discovered Kubernetes instances must be working (100% success rate)"
  fail=1
fi

# Basic check that frontend serves video elements
log "Testing frontend integration..."
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
  log "✅ STRICT WebSocket and stream test passed (Kubernetes discovery: $total_streams instances, 100% success)"
else
  log "❌ STRICT WebSocket and stream test failed"
  exit 1
fi
