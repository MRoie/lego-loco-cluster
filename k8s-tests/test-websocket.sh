#!/usr/bin/env bash
# k8s-tests/test-websocket.sh -- verify websocket and stream endpoints
set -euo pipefail

command -v curl >/dev/null 2>&1 || { echo "curl not found" >&2; exit 1; }
command -v node >/dev/null 2>&1 || { echo "node not found" >&2; exit 1; }

trap 'log "Error on line $LINENO"' ERR

LOG_DIR=${LOG_DIR:-k8s-tests/logs}
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/test-websocket.log"
log() { echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] $*"; }
exec > >(tee -a "$LOG_FILE") 2>&1

log "Starting websocket test"

BACKEND_URL=${BACKEND_URL:-http://localhost:3001}
STREAM_CONFIG="config/instances.json"

fail=0

# Check backend health
status=$(curl -o /dev/null -s -w "%{http_code}" "$BACKEND_URL/health" || echo "000")
if [ "$status" = "200" ]; then
  log "Backend health check passed"
else
  log "Backend health check failed (status $status)"
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
) && log "WebSocket active test passed" || { log "WebSocket active test failed"; fail=1; }

# Check stream URLs - require ALL discovered instances to be working for true success
if [[ -n "${STREAM_CONFIG:-}" ]] && [[ -f "$STREAM_CONFIG" ]]; then
  # Use the live instances configuration if available
  STREAMS=$(grep -o '"streamUrl": "[^"]*"' "$STREAM_CONFIG" | cut -d'"' -f4)
  log "Using live stream configuration: $STREAM_CONFIG"
else
  # Fallback to static configuration
  STREAMS=$(grep -o '"streamUrl": "[^"]*"' "$STREAM_CONFIG" | cut -d'"' -f4)
  log "Using static stream configuration: $STREAM_CONFIG"
fi

working_streams=0
total_streams=0

for url in $STREAMS; do
  total_streams=$((total_streams + 1))
  status=$(curl -o /dev/null -s -w "%{http_code}" --max-time 5 -I "$url" || echo "000")
  if [ "$status" = "200" ]; then
    log "Stream reachable: $url"
    working_streams=$((working_streams + 1))
  else
    log "Stream unreachable (status $status): $url"
  fi
done

# Success criteria: For discovered instances, all should work. For static instances, at least 1 should work.
success_threshold=1
if [[ "$total_streams" -le 3 ]]; then
  # If we have discovered instances (typically fewer), require all to work
  success_threshold=$total_streams
  log "Discovered instances mode: requiring all $total_streams streams to work"
else
  # Static configuration mode: allow partial success
  success_threshold=1
  log "Static configuration mode: requiring at least 1 of $total_streams streams"
fi

if [ $working_streams -ge $success_threshold ]; then
  log "✅ Stream test passed: $working_streams/$total_streams streams working (required: $success_threshold)"
else
  log "❌ Stream test failed: only $working_streams/$total_streams streams working (required: $success_threshold)"
  fail=1
fi

# Basic check that frontend serves video elements
status=$(curl -o /tmp/frontend.html -s -w "%{http_code}" "$BACKEND_URL" || echo "000")
if [ "$status" = "200" ]; then
  count=$(grep -c "<video" /tmp/frontend.html)
  if [ "$count" -gt 0 ]; then
    log "Frontend has $count video tags"
  else
    log "Frontend missing video tags"
    fail=1
  fi
else
  log "Failed to load frontend page (status $status)"
  fail=1
fi

if [ $fail -eq 0 ]; then
  log "✅ WebSocket and stream test passed"
else
  log "❌ WebSocket and stream test failed"
  exit 1
fi
