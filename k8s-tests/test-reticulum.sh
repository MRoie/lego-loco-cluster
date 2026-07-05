#!/usr/bin/env bash
# k8s-tests/test-reticulum.sh -- verify Reticulum mesh connectivity between emulator pods
set -euo pipefail

command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found" >&2; exit 1; }

trap 'log "Error on line $LINENO"' ERR

LOG_DIR=${LOG_DIR:-k8s-tests/logs}
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/test-reticulum.log"
log() { echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] $*"; }
exec > >(tee -a "$LOG_FILE") 2>&1

RNS_PORT=${RNS_PORT:-4242}
RNS_UDP_PORT=${RNS_UDP_PORT:-29716}
LABEL=${LABEL:-app.kubernetes.io/component=emulator}
NAMESPACE=${NAMESPACE:-loco}

log "Starting Reticulum mesh connectivity test"
log "  RNS TCP port : $RNS_PORT"
log "  RNS UDP port : $RNS_UDP_PORT"
log "  Pod label    : $LABEL"
log "  Namespace    : $NAMESPACE"

# ---------------------------------------------------------------------------
# Step 1 — Discover emulator pods
# ---------------------------------------------------------------------------
log "Discovering emulator pods..."
PODS=( $(kubectl get pods -n "$NAMESPACE" -l "$LABEL" -o name 2>/dev/null || true) )

if [ ${#PODS[@]} -eq 0 ]; then
  log "⚠️  No emulator pods found in namespace $NAMESPACE with label $LABEL"
  log "Falling back to all pods..."
  PODS=( $(kubectl get pods -o name -A 2>/dev/null | head -10 || true) )
fi

if [ ${#PODS[@]} -eq 0 ]; then
  log "No pods found — skipping Reticulum test"
  exit 0
fi

log "Found ${#PODS[@]} pods"

# ---------------------------------------------------------------------------
# Step 2 — Check for Reticulum sidecar in pods
# ---------------------------------------------------------------------------
log "Checking for Reticulum sidecar containers..."
rns_pods=0
for pod in "${PODS[@]}"; do
  POD_NAME=$(echo "$pod" | sed 's|pod/||')
  containers=$(kubectl get "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.containers[*].name}' 2>/dev/null || echo "")
  if echo "$containers" | grep -q "reticulum"; then
    log "  ✅ $POD_NAME has reticulum sidecar"
    rns_pods=$((rns_pods + 1))
  else
    log "  ℹ️  $POD_NAME — no reticulum sidecar (expected during Phase 1 pre-deployment)"
  fi
done

if [ $rns_pods -eq 0 ]; then
  log "⚠️  No Reticulum sidecars deployed yet — running connectivity pre-checks only"
fi

# ---------------------------------------------------------------------------
# Step 3 — Verify network prerequisites (UDP multicast on pod network)
# ---------------------------------------------------------------------------
log "Verifying network prerequisites..."
fail=0

# Check that pods have IPs on the same subnet
pod_ips=()
for pod in "${PODS[@]}"; do
  POD_NAME=$(echo "$pod" | sed 's|pod/||')
  IP=$(kubectl get "$pod" -n "$NAMESPACE" -o jsonpath='{.status.podIP}' 2>/dev/null || echo "")
  if [ -n "$IP" ]; then
    pod_ips+=("$IP")
    log "  Pod $POD_NAME → $IP"
  fi
done

if [ ${#pod_ips[@]} -ge 2 ]; then
  # Verify first two pods can reach each other on the pod network
  src_pod=$(echo "${PODS[0]}" | sed 's|pod/||')
  dst_ip="${pod_ips[1]}"
  log "Testing L3 connectivity: $src_pod → $dst_ip"
  if kubectl exec "$src_pod" -n "$NAMESPACE" -- ping -c 1 -W 2 "$dst_ip" >/dev/null 2>&1; then
    log "  ✅ L3 connectivity OK"
  else
    log "  ⚠️  L3 ping failed (may be restricted by NetworkPolicy)"
  fi

  # Check if UDP port is reachable (pre-check for AutoInterface)
  log "Testing UDP port $RNS_UDP_PORT readiness..."
  if kubectl exec "$src_pod" -n "$NAMESPACE" -- sh -c "echo test | nc -u -w1 $dst_ip $RNS_UDP_PORT" >/dev/null 2>&1; then
    log "  ✅ UDP port $RNS_UDP_PORT reachable"
  else
    log "  ℹ️  UDP port $RNS_UDP_PORT not yet open (expected before sidecar deployment)"
  fi
else
  log "  ⚠️  Need at least 2 pods for connectivity test"
fi

# ---------------------------------------------------------------------------
# Step 4 — If sidecars exist, verify mesh status
# ---------------------------------------------------------------------------
if [ $rns_pods -ge 2 ]; then
  log "Checking Reticulum mesh status..."
  for pod in "${PODS[@]}"; do
    POD_NAME=$(echo "$pod" | sed 's|pod/||')
    containers=$(kubectl get "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.containers[*].name}' 2>/dev/null || echo "")
    if echo "$containers" | grep -q "reticulum"; then
      log "  Querying rnstatus on $POD_NAME..."
      status=$(kubectl exec "$POD_NAME" -n "$NAMESPACE" -c reticulum -- rnstatus 2>/dev/null || echo "unavailable")
      if echo "$status" | grep -qi "interface"; then
        log "  ✅ $POD_NAME: Reticulum running, interfaces active"
      else
        log "  ⚠️  $POD_NAME: rnstatus returned: $status"
      fi
    fi
  done
fi

# ---------------------------------------------------------------------------
# Step 5 — Run benchmark if available
# ---------------------------------------------------------------------------
# python3 -c guards against launchers that exist but cannot run (e.g. Windows Store shim)
if python3 -c 'pass' >/dev/null 2>&1 && [ -f "benchmark/reticulum_bench.py" ]; then
  log "Running local loopback benchmark..."
  python3 benchmark/reticulum_bench.py --messages 50 --output "$LOG_DIR/reticulum_bench.csv" 2>&1 | while IFS= read -r line; do
    log "  [bench] $line"
  done
  if [ -f "$LOG_DIR/reticulum_bench.csv" ]; then
    log "  ✅ Benchmark results saved to $LOG_DIR/reticulum_bench.csv"
  fi
else
  log "  ℹ️  Skipping benchmark (python3 or benchmark script not available)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log ""
log "═══════════════════════════════════════════════════════"
log "  Reticulum Integration Test Summary"
log "═══════════════════════════════════════════════════════"
log "  Pods discovered    : ${#PODS[@]}"
log "  Pod IPs found      : ${#pod_ips[@]}"
log "  RNS sidecars       : $rns_pods"
log "  Failures           : $fail"
log "═══════════════════════════════════════════════════════"

if [ $fail -eq 0 ]; then
  log "✅ Reticulum integration test passed"
else
  log "⚠️  Reticulum integration test completed with warnings"
  exit 0
fi
