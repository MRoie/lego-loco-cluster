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

# Check stream URLs - only count working streams, don't fail if some are unavailable
STREAMS=$(grep -o '"streamUrl": "[^"]*"' "$STREAM_CONFIG" | cut -d'"' -f4)
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

if [ $working_streams -gt 0 ]; then
  log "At least $working_streams/$total_streams streams are working"
else
  log "No streams reachable (may be normal in test environment)"
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
