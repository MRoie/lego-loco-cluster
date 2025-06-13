#!/usr/bin/env bash
# k8s-tests/test-tcp.sh -- verify TCP connectivity between all pods and host
set -euo pipefail

LOG_DIR=${LOG_DIR:-k8s-tests/logs}
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/test-tcp.log"
log() { echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] $*"; }
exec > >(tee -a "$LOG_FILE") 2>&1

PORT=${PORT:-3390}
PODS=( $(kubectl get pods -o name 2>/dev/null || true) )

if [ ${#PODS[@]} -eq 0 ]; then
  log "No pods found, skipping TCP test"
  exit 0
fi

HOST_IP=$(ip route get 1 | awk '{print $(NF-2); exit}')

cleanup() {
  kill $HOST_PID >/dev/null 2>&1 || true
  for pod in "${PODS[@]}"; do
    kubectl exec "$pod" -- sh -c "kill \$(cat /tmp/nc.pid 2>/dev/null) 2>/dev/null; rm -f /tmp/nc.pid /tmp/tcp.log" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

# Start TCP listeners in pods
for pod in "${PODS[@]}"; do
  log "Starting listener in $pod on port $PORT"
  kubectl exec "$pod" -- sh -c "nohup nc -l -p $PORT >/tmp/tcp.log 2>&1 & echo \$! > /tmp/nc.pid" >/dev/null
done
sleep 2

# Start host listener
log "Starting host listener on port $PORT"
nc -l -p $PORT >/tmp/host_tcp.log &
HOST_PID=$!
sleep 1

fail=0

# Host -> pod
for pod in "${PODS[@]}"; do
  IP=$(kubectl get "$pod" -o jsonpath='{.status.podIP}')
  log "Host TCP to $pod ($IP)"
  if echo test | nc -w1 "$IP" $PORT >/dev/null 2>&1; then
    log "  reachable"
  else
    log "  FAILED"
    fail=1
  fi
done

# Pod -> host
for pod in "${PODS[@]}"; do
  log "$pod TCP to host ($HOST_IP)"
  if kubectl exec "$pod" -- sh -c "echo test | nc -w1 $HOST_IP $PORT" >/dev/null 2>&1; then
    log "  reachable"
  else
    log "  FAILED"
    fail=1
  fi
done

# Pod -> pod
for src in "${PODS[@]}"; do
  for dst in "${PODS[@]}"; do
    [ "$src" = "$dst" ] && continue
    DST_IP=$(kubectl get "$dst" -o jsonpath='{.status.podIP}')
    log "$src TCP to $dst ($DST_IP)"
    if kubectl exec "$src" -- sh -c "echo test | nc -w1 $DST_IP $PORT" >/dev/null 2>&1; then
      log "  reachable"
    else
      log "  FAILED"
      fail=1
    fi
  done
done

# Cleanup handled in trap

if [ $fail -eq 0 ]; then
  log "✅ TCP test passed"
else
  log "❌ TCP test failed"
  exit 1
fi
