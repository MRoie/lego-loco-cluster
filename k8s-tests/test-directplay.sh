#!/usr/bin/env bash
# ============================================================================
# test-directplay.sh — Verify DirectPlay port reachability across all pods
# ============================================================================
# Tests that TCP/UDP 2300 (Lego Loco) and 47624 (DirectPlay) are reachable
# between every pair of emulator pods in the cluster.
#
# Requires: kubectl, running emulator pods with shared L2 networking
# ============================================================================
set -euo pipefail

NAMESPACE=${NAMESPACE:-loco}
GAME_PORT=2300
DIRECTPLAY_PORT=47624
TIMEOUT=3
PASS_COUNT=0
FAIL_COUNT=0
LOG_DIR="k8s-tests/logs"

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/test-directplay-$(date +%Y%m%d-%H%M%S).log"

log() {
  echo "[$(date +'%H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Discover emulator pods
PODS=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=emulator \
  -o jsonpath='{range .items[*]}{.metadata.name},{.status.podIP}{"\n"}{end}' 2>/dev/null || true)

if [ -z "$PODS" ]; then
  log "⚠️  No emulator pods found in namespace $NAMESPACE"
  log "Trying broader label selector ..."
  PODS=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/part-of=lego-loco-cluster \
    -o jsonpath='{range .items[*]}{.metadata.name},{.status.podIP}{"\n"}{end}' 2>/dev/null || true)
fi

if [ -z "$PODS" ]; then
  log "❌ No emulator pods found. Ensure the cluster is running."
  exit 1
fi

# Parse pod names and IPs
declare -a POD_NAMES=()
declare -a POD_IPS=()
while IFS=, read -r name ip; do
  [ -z "$name" ] && continue
  POD_NAMES+=("$name")
  POD_IPS+=("$ip")
done <<< "$PODS"

POD_COUNT=${#POD_NAMES[@]}
log "Found $POD_COUNT emulator pod(s)"

# Test connectivity between each pair
test_port() {
  local from_pod="$1"
  local to_ip="$2"
  local port="$3"
  local proto="$4"

  if [ "$proto" = "tcp" ]; then
    kubectl exec -n "$NAMESPACE" "$from_pod" -- \
      timeout "$TIMEOUT" bash -c "echo | nc -w $TIMEOUT $to_ip $port" \
      >/dev/null 2>&1
  else
    kubectl exec -n "$NAMESPACE" "$from_pod" -- \
      timeout "$TIMEOUT" bash -c "echo test | nc -u -w $TIMEOUT $to_ip $port" \
      >/dev/null 2>&1
  fi
}

log ""
log "============================================================"
log "DirectPlay Port Reachability Test"
log "============================================================"
log ""

for ((i=0; i<POD_COUNT; i++)); do
  for ((j=0; j<POD_COUNT; j++)); do
    if [ "$i" -eq "$j" ]; then
      continue
    fi

    from="${POD_NAMES[$i]}"
    to="${POD_NAMES[$j]}"
    to_ip="${POD_IPS[$j]}"

    # Test game port 2300 TCP
    if test_port "$from" "$to_ip" "$GAME_PORT" "tcp"; then
      log "✅ $from → $to ($to_ip) TCP:$GAME_PORT OK"
      PASS_COUNT=$((PASS_COUNT + 1))
    else
      log "❌ $from → $to ($to_ip) TCP:$GAME_PORT FAIL"
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    # Test game port 2300 UDP
    if test_port "$from" "$to_ip" "$GAME_PORT" "udp"; then
      log "✅ $from → $to ($to_ip) UDP:$GAME_PORT OK"
      PASS_COUNT=$((PASS_COUNT + 1))
    else
      log "❌ $from → $to ($to_ip) UDP:$GAME_PORT FAIL"
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    # Test DirectPlay helper port 47624 TCP
    if test_port "$from" "$to_ip" "$DIRECTPLAY_PORT" "tcp"; then
      log "✅ $from → $to ($to_ip) TCP:$DIRECTPLAY_PORT OK"
      PASS_COUNT=$((PASS_COUNT + 1))
    else
      log "❌ $from → $to ($to_ip) TCP:$DIRECTPLAY_PORT FAIL"
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
  done
done

log ""
log "============================================================"
log "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
log "============================================================"

if [ "$FAIL_COUNT" -gt 0 ]; then
  log ""
  log "❌ DirectPlay port test FAILED"
  log "Ensure NETWORK_MODE=socket and shared L2 networking is configured."
  exit 1
fi

log "✅ All DirectPlay port tests passed"
exit 0
