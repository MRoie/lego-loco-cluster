#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# ci-validate-cluster.sh — CI Hybrid Cluster Validation
#
# Validates that a KIND (or minikube) cluster is healthy and all services
# are running. Designed to run as a CI step.
#
# Exit codes:
#   0 — All checks passed
#   1 — One or more checks failed
#
# Usage:
#   scripts/ci-validate-cluster.sh [--write-results]
#
# When --write-results is passed, writes a summary to
# docs/knowledge/qa-testing/ci-results/
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULTS_DIR="$PROJECT_ROOT/docs/knowledge/qa-testing/ci-results"
WRITE_RESULTS=false
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DATE_TAG=$(date -u +"%Y-%m-%d")

# Counters
PASS=0
FAIL=0
WARN=0
TOTAL=0
DETAILS=""

# ── Argument parsing ─────────────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --write-results) WRITE_RESULTS=true ;;
    --help|-h)
      echo "Usage: $0 [--write-results]"
      echo "  --write-results  Write results to docs/knowledge/qa-testing/ci-results/"
      exit 0
      ;;
  esac
done

# ── Colour helpers ────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; NC='\033[0m'; BOLD='\033[1m'
else
  GREEN=''; RED=''; YELLOW=''; NC=''; BOLD=''
fi

pass()  { PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); DETAILS+="  ✅ $1\n"; echo -e "  ${GREEN}✅ PASS${NC}: $1"; }
fail()  { FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); DETAILS+="  ❌ $1\n"; echo -e "  ${RED}❌ FAIL${NC}: $1"; }
warn()  { WARN=$((WARN+1)); DETAILS+="  ⚠️  $1\n"; echo -e "  ${YELLOW}⚠️  WARN${NC}: $1"; }
header(){ echo -e "\n${BOLD}── $1 ──${NC}"; }

# ── Pre-flight: kubectl available ─────────────────────────────────────────────
if ! command -v kubectl &>/dev/null; then
  echo -e "${RED}ERROR: kubectl not found in PATH${NC}"
  exit 1
fi

# ── Check: Cluster reachable ──────────────────────────────────────────────────
header "Cluster Connectivity"
if kubectl cluster-info &>/dev/null; then
  CLUSTER_NAME=$(kubectl config current-context 2>/dev/null || echo "unknown")
  pass "Cluster reachable (context: $CLUSTER_NAME)"
else
  fail "Cannot reach Kubernetes cluster"
  echo -e "\n${RED}FATAL: Cluster unreachable — aborting remaining checks.${NC}"
  exit 1
fi

# ── Check: Nodes Ready ───────────────────────────────────────────────────────
header "Node Health"
TOTAL_NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready' || true)

if [[ "$TOTAL_NODES" -eq 0 ]]; then
  fail "No nodes found in cluster"
elif [[ "$READY_NODES" -eq "$TOTAL_NODES" ]]; then
  pass "All $TOTAL_NODES node(s) are Ready"
else
  fail "$READY_NODES/$TOTAL_NODES nodes Ready"
fi

# ── Check: System Pods Running ────────────────────────────────────────────────
header "System Pods (kube-system)"
SYSTEM_PODS=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | wc -l)
RUNNING_SYSTEM=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -cE 'Running|Completed' || true)

if [[ "$SYSTEM_PODS" -eq 0 ]]; then
  fail "No system pods found"
elif [[ "$RUNNING_SYSTEM" -eq "$SYSTEM_PODS" ]]; then
  pass "All $SYSTEM_PODS system pod(s) Running/Completed"
else
  NOT_RUNNING=$((SYSTEM_PODS - RUNNING_SYSTEM))
  fail "$NOT_RUNNING system pod(s) not Running"
  kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -vE 'Running|Completed' || true
fi

# ── Check: Application Pods ──────────────────────────────────────────────────
APP_NS="loco"
header "Application Pods (namespace: $APP_NS)"
APP_PODS=$(kubectl get pods -n "$APP_NS" --no-headers 2>/dev/null | grep -v 'Completed' | wc -l)
RUNNING_APP=$(kubectl get pods -n "$APP_NS" --no-headers 2>/dev/null | grep -c 'Running' || true)

if [[ "$APP_PODS" -eq 0 ]]; then
  warn "No application pods in $APP_NS namespace (may be expected for bare cluster)"
elif [[ "$RUNNING_APP" -ge "$APP_PODS" ]]; then
  pass "All $APP_PODS application pod(s) Running in $APP_NS"
else
  NOT_RUNNING=$((APP_PODS - RUNNING_APP))
  fail "$NOT_RUNNING application pod(s) not Running in $APP_NS"
  kubectl get pods -n "$APP_NS" --no-headers 2>/dev/null | grep -vE 'Running|Completed' || true
fi

# ── Check: Services ──────────────────────────────────────────────────────────
header "Services"
SERVICES=$(kubectl get services -n "$APP_NS" --no-headers 2>/dev/null | wc -l)

if [[ "$SERVICES" -eq 0 ]]; then
  warn "No services found in $APP_NS namespace"
else
  pass "$SERVICES service(s) found in $APP_NS"
fi

# Check for key loco-cluster services
for svc in backend frontend emulator; do
  FOUND=$(kubectl get services -n "$APP_NS" --no-headers 2>/dev/null | grep -i "$svc" | head -1 || true)
  if [[ -n "$FOUND" ]]; then
    pass "Service matching '$svc' found: $(echo "$FOUND" | awk '{print $1}')"
  else
    warn "Service '$svc' not found in $APP_NS"
  fi
done

# ── Check: Endpoints Populated ────────────────────────────────────────────────
header "Endpoints"
ENDPOINTS=$(kubectl get endpoints -n "$APP_NS" --no-headers 2>/dev/null | wc -l)
EMPTY_EP=$(kubectl get endpoints -n "$APP_NS" --no-headers 2>/dev/null | awk '{if ($2 == "<none>") print $1}' || true)

if [[ "$ENDPOINTS" -eq 0 ]]; then
  warn "No endpoints found in $APP_NS"
else
  pass "$ENDPOINTS endpoint(s) found in $APP_NS"
fi

if [[ -n "$EMPTY_EP" ]]; then
  for ep in $EMPTY_EP; do
    warn "Endpoint '$ep' has no addresses in $APP_NS"
  done
fi

# ── Check: CoreDNS Running ───────────────────────────────────────────────────
header "DNS"
COREDNS=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -c 'coredns.*Running' || true)
if [[ "$COREDNS" -ge 1 ]]; then
  pass "CoreDNS running ($COREDNS replica(s))"
else
  fail "CoreDNS not running"
fi

# ── Check: Storage (PVCs) ────────────────────────────────────────────────────
header "Persistent Volume Claims"
PVCS=$(kubectl get pvc --no-headers --all-namespaces 2>/dev/null | wc -l)
BOUND_PVCS=$(kubectl get pvc --no-headers --all-namespaces 2>/dev/null | grep -c 'Bound' || true)

if [[ "$PVCS" -eq 0 ]]; then
  warn "No PVCs found (may be expected)"
elif [[ "$BOUND_PVCS" -eq "$PVCS" ]]; then
  pass "All $PVCS PVC(s) Bound"
else
  PENDING=$((PVCS - BOUND_PVCS))
  fail "$PENDING PVC(s) not Bound"
fi

# ── Check: NetworkPolicies ────────────────────────────────────────────────────
header "Network Policies"
NETPOL=$(kubectl get networkpolicies -n "$APP_NS" --no-headers 2>/dev/null | wc -l)
if [[ "$NETPOL" -gt 0 ]]; then
  pass "$NETPOL NetworkPolicy(ies) configured in $APP_NS"
else
  warn "No NetworkPolicies found in $APP_NS (open network)"
fi

# ── Check: RBAC (ClusterRoleBindings) ─────────────────────────────────────────
header "RBAC"
CRB=$(kubectl get clusterrolebindings --no-headers 2>/dev/null | wc -l)
if [[ "$CRB" -gt 0 ]]; then
  pass "$CRB ClusterRoleBinding(s) present"
else
  warn "No ClusterRoleBindings found"
fi

# ── Check: Helm Releases ─────────────────────────────────────────────────────
header "Helm Releases"
if command -v helm &>/dev/null; then
  RELEASES=$(helm list --all-namespaces --no-headers 2>/dev/null | wc -l)
  if [[ "$RELEASES" -gt 0 ]]; then
    pass "$RELEASES Helm release(s) deployed"
    helm list --all-namespaces --no-headers 2>/dev/null | while read -r line; do
      NAME=$(echo "$line" | awk '{print $1}')
      STATUS=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if($i=="deployed"||$i=="failed"||$i=="pending-upgrade"||$i=="superseded") print $i}')
      if [[ "$STATUS" == "deployed" ]]; then
        pass "Helm release '$NAME' status: deployed"
      else
        fail "Helm release '$NAME' status: $STATUS"
      fi
    done
  else
    warn "No Helm releases found"
  fi
else
  warn "helm not available — skipping Helm checks"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
header "Summary"
echo -e "  ${GREEN}Passed${NC}: $PASS"
echo -e "  ${RED}Failed${NC}: $FAIL"
echo -e "  ${YELLOW}Warnings${NC}: $WARN"
echo -e "  Total checks: $TOTAL"
echo ""

if [[ "$FAIL" -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}✅ CLUSTER VALIDATION PASSED${NC}"
  RESULT="PASS"
else
  echo -e "${RED}${BOLD}❌ CLUSTER VALIDATION FAILED ($FAIL failure(s))${NC}"
  RESULT="FAIL"
fi

# ── Write Results ─────────────────────────────────────────────────────────────
if [[ "$WRITE_RESULTS" == "true" ]]; then
  mkdir -p "$RESULTS_DIR"
  RESULT_FILE="$RESULTS_DIR/${DATE_TAG}-cluster-validation.md"

  cat > "$RESULT_FILE" <<EOF
# CI Cluster Validation — $DATE_TAG

**Timestamp**: $TIMESTAMP
**Result**: $RESULT
**Cluster**: $(kubectl config current-context 2>/dev/null || echo "unknown")

## Summary

| Metric | Value |
|--------|-------|
| Passed | $PASS |
| Failed | $FAIL |
| Warnings | $WARN |
| Total Checks | $TOTAL |

## Details

$(echo -e "$DETAILS")

## Cluster Info

\`\`\`
$(kubectl cluster-info 2>/dev/null || echo "cluster-info unavailable")
\`\`\`

## Nodes

\`\`\`
$(kubectl get nodes -o wide 2>/dev/null || echo "nodes unavailable")
\`\`\`

## Pods (all namespaces)

\`\`\`
$(kubectl get pods --all-namespaces -o wide 2>/dev/null || echo "pods unavailable")
\`\`\`

## Services

\`\`\`
$(kubectl get services --all-namespaces 2>/dev/null || echo "services unavailable")
\`\`\`
EOF

  echo -e "\n📝 Results written to: $RESULT_FILE"
fi

# Exit with appropriate code
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
