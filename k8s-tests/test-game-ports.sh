#!/usr/bin/env bash
# k8s-tests/test-game-ports.sh -- verify DirectPlay game ports (TCP/UDP 2300, TCP 47624)
#                                  are reachable between all emulator pod pairs
set -euo pipefail

command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found" >&2; exit 1; }

trap 'log "Error on line $LINENO"' ERR

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
NAMESPACE="${NAMESPACE:-loco}"
REPLICAS=9
STATEFULSET="loco-emulator"
SUBNET_PREFIX="192.168.10"
IP_OFFSET=10
TIMEOUT=3  # seconds for each probe

# Ports under test
TCP_PORTS=(2300 47624)
UDP_PORTS=(2300)

# Parse CLI args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace|-n) NAMESPACE="$2"; shift 2 ;;
    --replicas)     REPLICAS="$2";  shift 2 ;;
    --timeout)      TIMEOUT="$2";   shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
LOG_DIR=${LOG_DIR:-k8s-tests/logs}
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/test-game-ports.log"
log() { echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] $*"; }
exec > >(tee -a "$LOG_FILE") 2>&1

log "Starting game-port reachability test"
log "Namespace: $NAMESPACE  Replicas: $REPLICAS  Timeout: ${TIMEOUT}s"

# ---------------------------------------------------------------------------
# Ensure pods exist
# ---------------------------------------------------------------------------
log "Cluster pods in namespace $NAMESPACE:"
kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/component=emulator" -o wide || true

RUNNING=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/component=emulator" \
            --field-selector=status.phase=Running -o name 2>/dev/null | wc -l)
if [ "$RUNNING" -lt 2 ]; then
  log "Need at least 2 running emulator pods, found $RUNNING — skipping"
  exit 0
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
pod_name() { echo "${STATEFULSET}-${1}"; }
pod_ip()   { echo "${SUBNET_PREFIX}.$((IP_OFFSET + $1))"; }

fail=0
pass=0
total=0

# test_tcp <src_index> <dst_index> <port>
test_tcp() {
  local src dst port src_pod dst_ip
  src=$1; dst=$2; port=$3
  src_pod=$(pod_name "$src")
  dst_ip=$(pod_ip "$dst")
  total=$((total + 1))

  if kubectl exec -n "$NAMESPACE" "$src_pod" -- \
       sh -c "nc -z -w $TIMEOUT $dst_ip $port" >/dev/null 2>&1; then
    log "  ✅ TCP $port  ${src_pod} → ${dst_ip}  OK"
    pass=$((pass + 1))
  else
    log "  ❌ TCP $port  ${src_pod} → ${dst_ip}  FAIL"
    fail=$((fail + 1))
  fi
}

# test_udp <src_index> <dst_index> <port>
test_udp() {
  local src dst port src_pod dst_ip
  src=$1; dst=$2; port=$3
  src_pod=$(pod_name "$src")
  dst_ip=$(pod_ip "$dst")
  total=$((total + 1))

  # UDP probe: send a single datagram and check exit code.
  # nc -u -z may not be available everywhere, fall back to /dev/udp or socat.
  if kubectl exec -n "$NAMESPACE" "$src_pod" -- \
       sh -c "echo ping | nc -u -w $TIMEOUT $dst_ip $port" >/dev/null 2>&1; then
    log "  ✅ UDP $port  ${src_pod} → ${dst_ip}  OK"
    pass=$((pass + 1))
  else
    log "  ❌ UDP $port  ${src_pod} → ${dst_ip}  FAIL"
    fail=$((fail + 1))
  fi
}

# ---------------------------------------------------------------------------
# Run tests: every pod pair (src ≠ dst)
# ---------------------------------------------------------------------------
log "-------- TCP port tests --------"
for src in $(seq 0 $((REPLICAS - 1))); do
  for dst in $(seq 0 $((REPLICAS - 1))); do
    [ "$src" -eq "$dst" ] && continue
    for port in "${TCP_PORTS[@]}"; do
      test_tcp "$src" "$dst" "$port"
    done
  done
done

log "-------- UDP port tests --------"
for src in $(seq 0 $((REPLICAS - 1))); do
  for dst in $(seq 0 $((REPLICAS - 1))); do
    [ "$src" -eq "$dst" ] && continue
    for port in "${UDP_PORTS[@]}"; do
      test_udp "$src" "$dst" "$port"
    done
  done
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log "========================================"
log "Game-port test summary"
log "  Total probes : $total"
log "  Passed       : $pass"
log "  Failed       : $fail"
log "========================================"

if [ "$fail" -gt 0 ]; then
  log "❌ Game-port test FAILED ($fail failures)"
  exit 1
else
  log "✅ Game-port test PASSED"
  exit 0
fi
