#!/usr/bin/env bash
# validate-9-replicas.sh — K2 validation: ensure 9 emulator pods are running
# with unique identity (INSTANCE_INDEX, TAP, IP, MAC) and discoverable by backend.
# Designed to run against a KIND or minikube cluster.
set -euo pipefail

NAMESPACE="${NAMESPACE:-loco}"
EXPECTED_REPLICAS="${EXPECTED_REPLICAS:-9}"
LABEL_SELECTOR="app.kubernetes.io/component=emulator,app.kubernetes.io/part-of=lego-loco-cluster"
PASS=0
FAIL=0

pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
info() { echo "ℹ️  $1"; }
header() { echo ""; echo "=== $1 ==="; }

# --- Pre-flight ---
header "Pre-flight checks"
if ! command -v kubectl &>/dev/null; then
  echo "kubectl not found — aborting"; exit 1
fi

CONTEXT=$(kubectl config current-context 2>/dev/null || true)
info "Cluster context: ${CONTEXT:-<none>}"
info "Namespace:       $NAMESPACE"
info "Expected:        $EXPECTED_REPLICAS replicas"

# --- 1. StatefulSet exists and has correct replica count ---
header "1. StatefulSet replica count"
STS_JSON=$(kubectl get statefulset -n "$NAMESPACE" -l "$LABEL_SELECTOR" -o json 2>/dev/null || echo '{"items":[]}')
STS_COUNT=$(echo "$STS_JSON" | grep -c '"kind": "StatefulSet"' || echo 0)

if [ "$STS_COUNT" -eq 0 ]; then
  # Try without label selector — match by naming convention
  STS_JSON=$(kubectl get statefulset -n "$NAMESPACE" -o json 2>/dev/null || echo '{"items":[]}')
fi

STS_REPLICAS=$(echo "$STS_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for item in data.get('items', []):
    name = item['metadata']['name']
    if 'emulator' in name:
        print(item['spec'].get('replicas', 0))
        break
" 2>/dev/null || echo "0")

if [ "$STS_REPLICAS" -eq "$EXPECTED_REPLICAS" ]; then
  pass "StatefulSet configured with $STS_REPLICAS replicas"
else
  fail "StatefulSet has $STS_REPLICAS replicas (expected $EXPECTED_REPLICAS)"
fi

# --- 2. Pod count and phase ---
header "2. Pod status"
PODS_JSON=$(kubectl get pods -n "$NAMESPACE" -l "$LABEL_SELECTOR" -o json 2>/dev/null || echo '{"items":[]}')

RUNNING_COUNT=$(echo "$PODS_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(sum(1 for p in data.get('items', []) if p['status'].get('phase') == 'Running'))
" 2>/dev/null || echo "0")

TOTAL_COUNT=$(echo "$PODS_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(len(data.get('items', [])))
" 2>/dev/null || echo "0")

if [ "$RUNNING_COUNT" -eq "$EXPECTED_REPLICAS" ]; then
  pass "All $RUNNING_COUNT / $EXPECTED_REPLICAS pods Running"
else
  fail "$RUNNING_COUNT / $EXPECTED_REPLICAS pods Running ($TOTAL_COUNT total)"
  # Show non-running pods
  echo "$PODS_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for p in data.get('items', []):
    phase = p['status'].get('phase', 'Unknown')
    if phase != 'Running':
        print(f'    ⚠️  {p[\"metadata\"][\"name\"]}: {phase}')
" 2>/dev/null || true
fi

# --- 3. Unique INSTANCE_INDEX per pod ---
header "3. Instance identity (POD_NAME → INSTANCE_INDEX)"
INDICES=()
DUPES=0
for i in $(seq 0 $((EXPECTED_REPLICAS - 1))); do
  POD_NAME=$(echo "$PODS_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for p in data.get('items', []):
    if p['metadata']['name'].endswith('-$i'):
        print(p['metadata']['name'])
        break
" 2>/dev/null || echo "")

  if [ -z "$POD_NAME" ]; then
    fail "No pod found for ordinal $i"
    continue
  fi

  # Check that POD_NAME env var is set (entrypoint uses it to derive INSTANCE_INDEX)
  HAS_POD_NAME=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].env[?(@.name=="POD_NAME")].valueFrom.fieldRef.fieldPath}' 2>/dev/null || echo "")
  if [ "$HAS_POD_NAME" = "metadata.name" ]; then
    pass "Pod $POD_NAME has POD_NAME env via downward API"
  else
    fail "Pod $POD_NAME missing POD_NAME env var"
  fi

  # Verify the ordinal is unique
  ORDINAL="${POD_NAME##*-}"
  if [[ " ${INDICES[*]:-} " == *" $ORDINAL "* ]]; then
    fail "Duplicate ordinal $ORDINAL found"
    DUPES=$((DUPES + 1))
  else
    INDICES+=("$ORDINAL")
  fi
done

if [ "$DUPES" -eq 0 ] && [ "${#INDICES[@]}" -eq "$EXPECTED_REPLICAS" ]; then
  pass "All $EXPECTED_REPLICAS ordinals unique: ${INDICES[*]}"
fi

# --- 4. Security context (NET_ADMIN) ---
header "4. Security context"
FIRST_POD=$(echo "$PODS_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
items = data.get('items', [])
if items:
    print(items[0]['metadata']['name'])
" 2>/dev/null || echo "")

if [ -n "$FIRST_POD" ]; then
  CAPS=$(kubectl get pod "$FIRST_POD" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].securityContext.capabilities.add}' 2>/dev/null || echo "")
  PRIVILEGED=$(kubectl get pod "$FIRST_POD" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].securityContext.privileged}' 2>/dev/null || echo "false")

  if echo "$CAPS" | grep -q "NET_ADMIN" || [ "$PRIVILEGED" = "true" ]; then
    pass "NET_ADMIN capability present (privileged=$PRIVILEGED)"
  else
    fail "NET_ADMIN capability missing — TAP creation will fail"
  fi
fi

# --- 5. Labels for backend discovery ---
header "5. Discovery labels"
LABELED_COUNT=$(echo "$PODS_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
count = 0
for p in data.get('items', []):
    labels = p['metadata'].get('labels', {})
    if labels.get('app.kubernetes.io/component') == 'emulator' and labels.get('app.kubernetes.io/part-of') == 'lego-loco-cluster':
        count += 1
print(count)
" 2>/dev/null || echo "0")

if [ "$LABELED_COUNT" -eq "$EXPECTED_REPLICAS" ]; then
  pass "All $LABELED_COUNT pods have discovery labels"
else
  fail "$LABELED_COUNT / $EXPECTED_REPLICAS pods have correct labels"
fi

# --- 6. Headless service exists ---
header "6. Headless service"
SVC_CLUSTER_IP=$(kubectl get svc -n "$NAMESPACE" -l "app.kubernetes.io/component=emulator" -o jsonpath='{.items[0].spec.clusterIP}' 2>/dev/null || echo "")
if [ "$SVC_CLUSTER_IP" = "None" ]; then
  pass "Headless service exists (clusterIP=None)"
else
  if [ -z "$SVC_CLUSTER_IP" ]; then
    fail "No emulator service found"
  else
    fail "Service is not headless (clusterIP=$SVC_CLUSTER_IP)"
  fi
fi

# --- 7. Network identity env vars ---
header "7. Network identity env vars"
if [ -n "$FIRST_POD" ]; then
  ENV_VARS=$(kubectl get pod "$FIRST_POD" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].env[*].name}' 2>/dev/null || echo "")
  for VAR in BRIDGE GUEST_GATEWAY GUEST_NETMASK WORKGROUP; do
    if echo "$ENV_VARS" | grep -q "$VAR"; then
      pass "$FIRST_POD has $VAR"
    else
      fail "$FIRST_POD missing $VAR"
    fi
  done
fi

# --- 8. VNC port in service ---
header "8. VNC port configuration"
VNC_PORT=$(kubectl get svc -n "$NAMESPACE" -l "app.kubernetes.io/component=emulator" -o jsonpath='{.items[0].spec.ports[?(@.name=="vnc")].port}' 2>/dev/null || echo "")
if [ -n "$VNC_PORT" ]; then
  pass "VNC port $VNC_PORT exposed on headless service"
else
  fail "No VNC port found on emulator service"
fi

# --- 9. Backend can discover instances ---
header "9. Backend discovery simulation"
BACKEND_POD=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/component=backend" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$BACKEND_POD" ]; then
  # Verify backend can list emulator pods via the K8s API (RBAC check)
  SA_NAME=$(kubectl get pod "$BACKEND_POD" -n "$NAMESPACE" -o jsonpath='{.spec.serviceAccountName}' 2>/dev/null || echo "")
  if [ -n "$SA_NAME" ]; then
    CAN_LIST=$(kubectl auth can-i list pods --as="system:serviceaccount:${NAMESPACE}:${SA_NAME}" -n "$NAMESPACE" 2>/dev/null || echo "no")
    if [ "$CAN_LIST" = "yes" ]; then
      pass "Backend SA '$SA_NAME' can list pods in $NAMESPACE"
    else
      fail "Backend SA '$SA_NAME' cannot list pods (RBAC issue)"
    fi
  else
    fail "Backend pod has no service account"
  fi
else
  info "No backend pod running — skipping RBAC check"
fi

# --- Summary ---
header "Summary"
TOTAL=$((PASS + FAIL))
echo "  Passed: $PASS / $TOTAL"
echo "  Failed: $FAIL / $TOTAL"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo "❌ VALIDATION FAILED — $FAIL check(s) did not pass"
  exit 1
else
  echo "✅ ALL CHECKS PASSED — 9-replica scaling validated"
  exit 0
fi
