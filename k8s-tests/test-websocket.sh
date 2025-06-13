#!/usr/bin/env bash
# k8s-tests/test-websocket.sh -- verify websocket and stream endpoints
set -euo pipefail

LOG_DIR=${LOG_DIR:-k8s-tests/logs}
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/test-websocket.log"
log() { echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] $*"; }
exec > >(tee -a "$LOG_FILE") 2>&1

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
const url = process.argv[2] + '/signal';
const ws = new WebSocket(url);
const timer = setTimeout(() => { console.error('timeout'); process.exit(1); }, 5000);
ws.on('open', () => { clearTimeout(timer); ws.close(); });
ws.on('close', () => process.exit(0));
ws.on('error', () => process.exit(1));
NODE
) && log "WebSocket signal test passed" || { log "WebSocket signal test failed"; fail=1; }

# Check stream URLs
STREAMS=$(grep -o '"streamUrl": "[^"]*"' "$STREAM_CONFIG" | cut -d'"' -f4)
for url in $STREAMS; do
  status=$(curl -o /dev/null -s -w "%{http_code}" --max-time 5 -I "$url" || echo "000")
  if [ "$status" = "200" ]; then
    log "Stream reachable: $url"
  else
    log "Stream unreachable (status $status): $url"
    fail=1
  fi
done

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
