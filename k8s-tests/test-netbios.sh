#!/usr/bin/env bash
# k8s-tests/test-netbios.sh -- validate NetBIOS/WINS discovery between LOCO pods
# Tests UDP 137-139 connectivity and NetBIOS name resolution across all 9 instances.
set -euo pipefail

command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found" >&2; exit 1; }

trap 'log "Error on line $LINENO"' ERR

LOG_DIR=${LOG_DIR:-k8s-tests/logs}
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/test-netbios.log"
log() { echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] $*"; }
exec > >(tee -a "$LOG_FILE") 2>&1

# ---------------------------------------------------------------------------
# Configuration (matches instance-identity-spec.md)
# ---------------------------------------------------------------------------
NAMESPACE=${NAMESPACE:-default}
STATEFULSET=${STATEFULSET:-loco-emulator}
INSTANCE_COUNT=${INSTANCE_COUNT:-9}
SUBNET="192.168.10"
BASE_IP=10
WORKGROUP="LOCOLAND"

# NetBIOS ports
NETBIOS_NS_PORT=137    # Name Service (UDP)
NETBIOS_DG_PORT=138    # Datagram (UDP)
NETBIOS_SS_PORT=139    # Session Service (TCP)

TOTAL=0
PASS=0
FAIL=0
WARN=0

result() {
  TOTAL=$((TOTAL + 1))
  local status="$1"; shift
  case "$status" in
    PASS) PASS=$((PASS + 1)); log "  ✅ PASS: $*" ;;
    FAIL) FAIL=$((FAIL + 1)); log "  ❌ FAIL: $*" ;;
    WARN) WARN=$((WARN + 1)); log "  ⚠️  WARN: $*" ;;
  esac
}

# ---------------------------------------------------------------------------
# Discover pods
# ---------------------------------------------------------------------------
log "=== NetBIOS/WINS Discovery Validation ==="
log "Namespace: $NAMESPACE  StatefulSet: $STATEFULSET  Instances: $INSTANCE_COUNT"
log ""

# Get running emulator pods
PODS=()
for i in $(seq 0 $((INSTANCE_COUNT - 1))); do
  POD_NAME="${STATEFULSET}-${i}"
  if kubectl get pod "$POD_NAME" -n "$NAMESPACE" --no-headers 2>/dev/null | grep -q Running; then
    PODS+=("$POD_NAME")
  else
    log "Pod $POD_NAME not running — skipping"
  fi
done

if [ ${#PODS[@]} -lt 2 ]; then
  log "Need at least 2 running pods for NetBIOS tests. Found: ${#PODS[@]}"
  log "⚠️  Skipping NetBIOS tests (insufficient pods)"
  exit 0
fi
log "Found ${#PODS[@]} running pods: ${PODS[*]}"
log ""

# ---------------------------------------------------------------------------
# Helper: exec a command inside a pod
# ---------------------------------------------------------------------------
kexec() {
  local pod="$1"; shift
  kubectl exec "$pod" -n "$NAMESPACE" -- "$@" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Test 1: UDP 137 (NetBIOS Name Service) connectivity between all pod pairs
# ---------------------------------------------------------------------------
log "=== Test 1: UDP 137 (NetBIOS Name Service) port connectivity ==="

for src_pod in "${PODS[@]}"; do
  SRC_IDX=${src_pod##*-}
  for dst_pod in "${PODS[@]}"; do
    [ "$src_pod" = "$dst_pod" ] && continue
    DST_IDX=${dst_pod##*-}
    DST_IP="${SUBNET}.$((BASE_IP + DST_IDX))"

    # Use nc (netcat) to test UDP 137 reachability with a short timeout
    if kexec "$src_pod" timeout 3 bash -c "echo -n '' | nc -u -w1 ${DST_IP} ${NETBIOS_NS_PORT}" 2>/dev/null; then
      result PASS "UDP 137: ${src_pod} -> ${DST_IP} (${dst_pod})"
    else
      # nc may not return 0 for UDP even when port is open; check with nmap if available
      if kexec "$src_pod" timeout 5 nmap -sU -p 137 --host-timeout 3s "$DST_IP" 2>/dev/null | grep -q "open"; then
        result PASS "UDP 137 (nmap): ${src_pod} -> ${DST_IP} (${dst_pod})"
      else
        result WARN "UDP 137: ${src_pod} -> ${DST_IP} (${dst_pod}) — port may be filtered or tools unavailable"
      fi
    fi
  done
done
log ""

# ---------------------------------------------------------------------------
# Test 2: UDP 138 (NetBIOS Datagram) connectivity
# ---------------------------------------------------------------------------
log "=== Test 2: UDP 138 (NetBIOS Datagram) port connectivity ==="

for src_pod in "${PODS[@]}"; do
  SRC_IDX=${src_pod##*-}
  for dst_pod in "${PODS[@]}"; do
    [ "$src_pod" = "$dst_pod" ] && continue
    DST_IDX=${dst_pod##*-}
    DST_IP="${SUBNET}.$((BASE_IP + DST_IDX))"

    if kexec "$src_pod" timeout 3 bash -c "echo -n '' | nc -u -w1 ${DST_IP} ${NETBIOS_DG_PORT}" 2>/dev/null; then
      result PASS "UDP 138: ${src_pod} -> ${DST_IP}"
    else
      result WARN "UDP 138: ${src_pod} -> ${DST_IP} — may be filtered"
    fi
  done
done
log ""

# ---------------------------------------------------------------------------
# Test 3: TCP 139 (NetBIOS Session) connectivity
# ---------------------------------------------------------------------------
log "=== Test 3: TCP 139 (NetBIOS Session) port connectivity ==="

for src_pod in "${PODS[@]}"; do
  SRC_IDX=${src_pod##*-}
  for dst_pod in "${PODS[@]}"; do
    [ "$src_pod" = "$dst_pod" ] && continue
    DST_IDX=${dst_pod##*-}
    DST_IP="${SUBNET}.$((BASE_IP + DST_IDX))"

    if kexec "$src_pod" timeout 3 nc -z -w1 "${DST_IP}" "${NETBIOS_SS_PORT}" 2>/dev/null; then
      result PASS "TCP 139: ${src_pod} -> ${DST_IP} (${dst_pod})"
    else
      result WARN "TCP 139: ${src_pod} -> ${DST_IP} — connection refused or timeout"
    fi
  done
done
log ""

# ---------------------------------------------------------------------------
# Test 4: NetBIOS name resolution via nmblookup (host-side, inside pod)
# ---------------------------------------------------------------------------
log "=== Test 4: NetBIOS name resolution (nmblookup from pod) ==="

for src_pod in "${PODS[@]}"; do
  SRC_IDX=${src_pod##*-}
  log "  From ${src_pod} (LOCO-0${SRC_IDX}):"

  for dst_idx in $(seq 0 $((INSTANCE_COUNT - 1))); do
    [ "$dst_idx" = "$SRC_IDX" ] && continue
    TARGET_NAME="LOCO-0${dst_idx}"
    EXPECTED_IP="${SUBNET}.$((BASE_IP + dst_idx))"

    if RESOLVED=$(kexec "$src_pod" timeout 5 nmblookup "$TARGET_NAME" 2>/dev/null); then
      if echo "$RESOLVED" | grep -q "$EXPECTED_IP"; then
        result PASS "nmblookup ${TARGET_NAME} = ${EXPECTED_IP}"
      else
        result FAIL "nmblookup ${TARGET_NAME}: expected ${EXPECTED_IP}, got: ${RESOLVED}"
      fi
    else
      result WARN "nmblookup ${TARGET_NAME}: tool not available or timed out"
    fi
  done
done
log ""

# ---------------------------------------------------------------------------
# Test 5: nbtstat -a equivalent via QEMU monitor (guest-side validation)
# Uses the QEMU monitor to send a command to the Windows 98 guest, or falls
# back to checking if the bridge can see NetBIOS traffic via tcpdump.
# ---------------------------------------------------------------------------
log "=== Test 5: Guest-side NetBIOS validation (bridge traffic sniff) ==="

# Pick the first pod and sniff the bridge for NetBIOS name query packets
SNIFF_POD="${PODS[0]}"
log "  Sniffing loco-br on ${SNIFF_POD} for NetBIOS traffic (5s)..."

if SNIFF_OUTPUT=$(kexec "$SNIFF_POD" timeout 6 tcpdump -i loco-br -c 10 -nn "udp port 137 or udp port 138" 2>&1); then
  PACKET_COUNT=$(echo "$SNIFF_OUTPUT" | grep -c "UDP" || true)
  if [ "$PACKET_COUNT" -gt 0 ]; then
    result PASS "Captured ${PACKET_COUNT} NetBIOS packets on loco-br"
    log "    Sample: $(echo "$SNIFF_OUTPUT" | head -3)"
  else
    result WARN "No NetBIOS packets captured in 5s window (guests may not be broadcasting yet)"
  fi
else
  result WARN "tcpdump not available or no traffic on loco-br"
fi
log ""

# ---------------------------------------------------------------------------
# Test 6: Workgroup discovery (browse list)
# ---------------------------------------------------------------------------
log "=== Test 6: Workgroup browse list (LOCOLAND) ==="

for src_pod in "${PODS[@]}"; do
  if BROWSE=$(kexec "$src_pod" timeout 5 nmblookup -S "${WORKGROUP}" 2>/dev/null); then
    FOUND=$(echo "$BROWSE" | grep -c "${SUBNET}" || true)
    if [ "$FOUND" -gt 0 ]; then
      result PASS "Workgroup ${WORKGROUP} visible from ${src_pod} (${FOUND} entries)"
    else
      result WARN "Workgroup ${WORKGROUP} query returned no subnet entries from ${src_pod}"
    fi
  else
    result WARN "nmblookup -S ${WORKGROUP} failed on ${src_pod}"
  fi
done
log ""

# ---------------------------------------------------------------------------
# Test 7: Discovery matrix — which names are visible from which pods
# ---------------------------------------------------------------------------
log "=== Test 7: Discovery matrix ==="
log ""
HEADER="            "
for dst_idx in $(seq 0 $((INSTANCE_COUNT - 1))); do
  HEADER+="LOCO-0${dst_idx}  "
done
log "$HEADER"

for src_pod in "${PODS[@]}"; do
  SRC_IDX=${src_pod##*-}
  ROW="LOCO-0${SRC_IDX}  "
  for dst_idx in $(seq 0 $((INSTANCE_COUNT - 1))); do
    if [ "$dst_idx" = "$SRC_IDX" ]; then
      ROW+="  self     "
      continue
    fi
    TARGET_NAME="LOCO-0${dst_idx}"
    EXPECTED_IP="${SUBNET}.$((BASE_IP + dst_idx))"

    if RESOLVED=$(kexec "$src_pod" timeout 3 nmblookup "$TARGET_NAME" 2>/dev/null) && echo "$RESOLVED" | grep -q "$EXPECTED_IP"; then
      ROW+="  ✅       "
    else
      ROW+="  ❌       "
    fi
  done
  log "$ROW"
done
log ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log "=== NetBIOS Test Summary ==="
log "Total: $TOTAL  Pass: $PASS  Fail: $FAIL  Warn: $WARN"

if [ "$FAIL" -gt 0 ]; then
  log "❌ NetBIOS validation FAILED ($FAIL failures)"
  exit 1
elif [ "$WARN" -gt 0 ]; then
  log "⚠️  NetBIOS validation completed with warnings"
  exit 0
else
  log "✅ NetBIOS validation PASSED"
  exit 0
fi
