#!/usr/bin/env bash
# k8s-tests/test-broadcast.sh -- confirm game sessions are visible across containers
set -euo pipefail

command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found" >&2; exit 1; }
command -v tcpdump >/dev/null 2>&1 || { echo "tcpdump not found" >&2; exit 1; }
command -v nc >/dev/null 2>&1 || { echo "nc not found" >&2; exit 1; }

trap 'log "Error on line $LINENO"' ERR

LOG_DIR=${LOG_DIR:-k8s-tests/logs}
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/test-broadcast.log"
log() { echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] $*"; }
exec > >(tee -a "$LOG_FILE") 2>&1

log "Starting broadcast test"

PORT=${PORT:-2242}
PODS=( $(kubectl get pods -o name 2>/dev/null || true) )

if [ ${#PODS[@]} -le 1 ]; then
  log "Not enough pods for broadcast test"
  exit 0
fi

# Ensure tcpdump exists in pods
if ! kubectl exec "${PODS[0]}" -- which tcpdump >/dev/null 2>&1; then
  log "tcpdump not available in pods; skipping broadcast test"
  exit 0
fi

fail=0

log "Starting listeners..."
for pod in "${PODS[@]}"; do
  log "Listening in $pod"
  kubectl exec "$pod" -- sh -c "rm -f /tmp/bcast.log; timeout 10s tcpdump -n -i any udp port $PORT > /tmp/bcast.log &" >/dev/null
done
sleep 2

log "Sending broadcast packets..."
for pod in "${PODS[@]}"; do
  log "Broadcasting from $pod"
  kubectl exec "$pod" -- sh -c "echo loco | nc -b -u 255.255.255.255 $PORT" || true
  sleep 1
done
sleep 5

log "Checking results..."
for pod in "${PODS[@]}"; do
  if kubectl exec "$pod" -- grep -q "loco" /tmp/bcast.log >/dev/null 2>&1; then
    log "  $pod received broadcast"
  else
    log "  $pod did NOT receive broadcast"
    fail=1
  fi
  kubectl exec "$pod" -- rm -f /tmp/bcast.log >/dev/null 2>&1 || true
done

if [ $fail -eq 0 ]; then
  log "✅ Broadcast test passed"
else
  log "❌ Broadcast test failed"
  exit 1
fi
