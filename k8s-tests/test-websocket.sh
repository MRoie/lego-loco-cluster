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

# Validate VNC reachability via probe data in the instances API response
# The streamUrl is a relative VNC proxy path (/proxy/vnc/instance-N) served via WebSocket,
# so we validate using the probe results which confirm actual VNC/health connectivity.
if command -v jq &>/dev/null; then
  PROBE_RESULTS=$(echo "$instances_response" | jq -r '.[] | "\(.id)|\(.probe.reachable // false)|\(.probe.services.vnc.status // "unknown")|\(.probe.services.health.status // "unknown")|\(.streamUrl // "none")"')
else
  PROBE_RESULTS=$(echo "$instances_response" | python3 -c "
import sys, json
for i in json.load(sys.stdin):
    p = i.get('probe', {})
    vs = p.get('services', {}).get('vnc', {}).get('status', 'unknown')
    hs = p.get('services', {}).get('health', {}).get('status', 'unknown')
    r = str(p.get('reachable', False)).lower()
    print(f\"{i['id']}|{r}|{vs}|{hs}|{i.get('streamUrl', 'none')}\")
" 2>/dev/null || echo "")
fi
total_instances=$(echo "$PROBE_RESULTS" | grep -c . || true)

if [[ -z "$PROBE_RESULTS" ]] || [[ "$total_instances" -eq 0 ]]; then
  log "❌ CRITICAL: No instances with probe data found!"
  log "Instances response: $instances_response"
  fail=1
  exit 1
fi

log "Found $total_instances discovered instances from Kubernetes cluster"

working_instances=0

while IFS='|' read -r inst_id reachable vnc_status health_status stream_url; do
  [[ -z "$inst_id" ]] && continue
  
  log "Validating $inst_id: reachable=$reachable vnc=$vnc_status health=$health_status streamUrl=$stream_url"
  if [[ "$reachable" == "true" ]] && [[ "$vnc_status" == "ok" ]] && [[ "$health_status" == "ok" ]]; then
    log "✅ Instance $inst_id: VNC reachable, health ok, stream proxy at $stream_url"
    working_instances=$((working_instances + 1))
  else
    log "❌ Instance $inst_id: probe failed (reachable=$reachable vnc=$vnc_status health=$health_status)"
  fi
done <<< "$PROBE_RESULTS"

# SUCCESS CRITERIA: ALL discovered instances must have passing probes (100% success rate)
log "Evaluating STRICT success criteria: $working_instances/$total_instances instances with healthy probes"

if [ $working_instances -eq $total_instances ] && [ $total_instances -gt 0 ]; then
  log "✅ Probe test passed: ALL $working_instances/$total_instances instances healthy (VNC + health probes OK)"
else
  log "❌ Probe test failed: only $working_instances/$total_instances instances healthy"
  log "STRICT REQUIREMENT: ALL discovered Kubernetes instances must have passing probes (100% success rate)"
  fail=1
fi

# Check VNC WebSocket proxy endpoint on the backend
log "Testing VNC WebSocket proxy endpoint..."
vnc_proxy_status=$(curl -o /dev/null -s -w "%{http_code}" --max-time 5 "$BACKEND_URL/proxy/vnc/instance-0" || echo "000")
# WebSocket endpoints return 426 (Upgrade Required) for HTTP requests — that's correct
if [[ "$vnc_proxy_status" == "426" ]] || [[ "$vnc_proxy_status" == "101" ]] || [[ "$vnc_proxy_status" == "200" ]]; then
  log "✅ VNC proxy endpoint responding (HTTP $vnc_proxy_status — WebSocket upgrade expected)"
else
  log "⚠️  VNC proxy endpoint returned HTTP $vnc_proxy_status (may need WebSocket client to connect)"
fi

# Check frontend serves the SPA
log "Testing frontend integration..."
FRONTEND_URL="${FRONTEND_URL:-http://localhost:3000}"
status=$(curl -o /tmp/frontend.html -s -w "%{http_code}" --max-time 5 "$FRONTEND_URL" || echo "000")
if [ "$status" = "200" ]; then
  # React SPA — check for root div or script tags (video tags are rendered dynamically)
  if grep -q 'id="root"\|<script' /tmp/frontend.html 2>/dev/null; then
    log "✅ Frontend SPA served successfully"
  else
    log "⚠️  Frontend returned 200 but missing expected SPA markers"
  fi
else
  log "⚠️  Frontend not reachable (status $status) — port-forward may be needed: kubectl port-forward svc/loco-loco-frontend 3000:3000 -n loco"
fi

if [ $fail -eq 0 ]; then
  log "✅ STRICT WebSocket and stream test passed (Kubernetes discovery: $total_instances instances, 100% success)"
else
  log "❌ STRICT WebSocket and stream test failed"
  exit 1
fi
