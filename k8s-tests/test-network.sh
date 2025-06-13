#!/usr/bin/env bash
# k8s-tests/test-network.sh -- verify L2/L3 connectivity between all pods and host
set -euo pipefail

LOG_DIR=${LOG_DIR:-k8s-tests/logs}
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/test-network.log"
log() { echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] $*"; }
exec > >(tee -a "$LOG_FILE") 2>&1

PODS=(
  $(kubectl get pods -o name 2>/dev/null || true)
)

if [ ${#PODS[@]} -eq 0 ]; then
  log "No pods found, skipping network test"
  exit 0
fi

HOST_IP=$(ip route get 1 | awk '{print $(NF-2); exit}')

fail=0

for pod in "${PODS[@]}"; do
  IP=$(kubectl get "$pod" -o jsonpath='{.status.podIP}')
  log "Host -> $pod ($IP)"
  if ping -c1 -W1 "$IP" >/dev/null 2>&1; then
    log "  reachable"
  else
    log "  FAILED"
    fail=1
  fi

done

for pod in "${PODS[@]}"; do
  log "$pod -> host ($HOST_IP)"
  if kubectl exec "$pod" -- ping -c1 -W1 "$HOST_IP" >/dev/null 2>&1; then
    log "  reachable"
  else
    log "  FAILED"
    fail=1
  fi
done

for src in "${PODS[@]}"; do
  for dst in "${PODS[@]}"; do
    [ "$src" = "$dst" ] && continue
    DST_IP=$(kubectl get "$dst" -o jsonpath='{.status.podIP}')
    log "$src -> $dst ($DST_IP)"
    if kubectl exec "$src" -- ping -c1 -W1 "$DST_IP" >/dev/null 2>&1; then
      log "  reachable"
    else
      log "  FAILED"
      fail=1
    fi
  done
done

if [ $fail -eq 0 ]; then
  log "✅ Network test passed"
else
  log "❌ Network test failed"
  exit 1
fi
