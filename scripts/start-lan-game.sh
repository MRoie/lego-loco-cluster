#!/usr/bin/env bash
# ============================================================================
# start-lan-game.sh — one command from zero to an active Lego Loco LAN game
# ============================================================================
# Brings the cluster up, deploys the 2-instance LAN configuration, drives
# both Win98 guests into a multiplayer session via QMP, and captures proof
# artifacts (guest screendumps + optional dashboard loading video).
#
# Usage:
#   scripts/start-lan-game.sh [options]
#
# Options:
#   --cluster NAME     kind cluster name (default: loco)
#   --namespace NS     kubernetes namespace (default: loco)
#   --values FILE      helm values overlay (default: helm/loco-chart/values-lan-test.yaml)
#   --proof-dir DIR    where proof artifacts land (default: proof/lan-game-<timestamp>)
#   --skip-cluster     assume the cluster and images already exist
#   --skip-build       do not rebuild backend/frontend images
#   --skip-game        deploy + wait only; skip the in-game QMP choreography
#   --record           also record the dashboard's progressive loading (playwright)
#
# Requires: docker, kind, kubectl, helm, python3. Playwright only with --record.
# The in-game choreography needs the emulator image whose guests were baked
# network-ready (see docs/LAN_MULTIPLAYER_AND_GHCR_RUNBOOK.md).
# ============================================================================
set -euo pipefail

CLUSTER=loco
NAMESPACE=loco
VALUES=helm/loco-chart/values-lan-test.yaml
PROOF_DIR=""
SKIP_CLUSTER=false
SKIP_BUILD=false
SKIP_GAME=false
RECORD=false

while [ $# -gt 0 ]; do
  case "$1" in
    --cluster) CLUSTER="$2"; shift 2;;
    --namespace) NAMESPACE="$2"; shift 2;;
    --values) VALUES="$2"; shift 2;;
    --proof-dir) PROOF_DIR="$2"; shift 2;;
    --skip-cluster) SKIP_CLUSTER=true; shift;;
    --skip-build) SKIP_BUILD=true; shift;;
    --skip-game) SKIP_GAME=true; shift;;
    --record) RECORD=true; shift;;
    *) echo "Unknown option: $1" >&2; exit 2;;
  esac
done

STAMP=$(date +%Y%m%d-%H%M%S)
PROOF_DIR=${PROOF_DIR:-proof/lan-game-$STAMP}
mkdir -p "$PROOF_DIR"
LOG="$PROOF_DIR/start-lan-game.log"

log() { echo "[$(date +'%H:%M:%S')] $*" | tee -a "$LOG"; }

log "=== Lego Loco LAN game quickstart ==="
log "cluster=$CLUSTER namespace=$NAMESPACE values=$VALUES proof=$PROOF_DIR"

# ---------------------------------------------------------------------------
# 1. Cluster
# ---------------------------------------------------------------------------
if [ "$SKIP_CLUSTER" != true ]; then
  if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
    log "Creating kind cluster '$CLUSTER'..."
    kind create cluster --name "$CLUSTER" --wait 180s
  else
    log "kind cluster '$CLUSTER' already exists"
  fi
fi
KCTX="kind-$CLUSTER"
kubectl config use-context "$KCTX" >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# 2. Images
# ---------------------------------------------------------------------------
if [ "$SKIP_BUILD" != true ]; then
  log "Building backend image (context is allowlisted — see .dockerignore)..."
  docker build -f backend/Dockerfile --target production -t lego-loco-backend:local . >>"$LOG" 2>&1
  log "Building frontend image..."
  docker build -f frontend/Dockerfile --target production -t lego-loco-frontend:local ./frontend >>"$LOG" 2>&1
  log "Loading app images into kind..."
  kind load docker-image lego-loco-backend:local --name "$CLUSTER" >>"$LOG" 2>&1
  kind load docker-image lego-loco-frontend:local --name "$CLUSTER" >>"$LOG" 2>&1
fi

EMU_IMAGE=$(grep -A2 '^emulator:' "$VALUES" | grep 'image:' | awk '{print $2}')
EMU_TAG=$(grep -A3 '^emulator:' "$VALUES" | grep 'tag:' | awk '{print $2}')
if ! docker exec "${CLUSTER}-control-plane" crictl images 2>/dev/null | grep -q "$EMU_IMAGE"; then
  if docker image inspect "$EMU_IMAGE:$EMU_TAG" >/dev/null 2>&1; then
    log "Loading emulator image $EMU_IMAGE:$EMU_TAG into kind (large, one-time)..."
    kind load docker-image "$EMU_IMAGE:$EMU_TAG" --name "$CLUSTER" >>"$LOG" 2>&1
  else
    log "WARNING: emulator image $EMU_IMAGE:$EMU_TAG not present locally."
    log "         Build it per docs/LAN_MULTIPLAYER_AND_GHCR_RUNBOOK.md §2.1 first."
  fi
fi

# ---------------------------------------------------------------------------
# 3. Deploy
# ---------------------------------------------------------------------------
kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"
log "Deploying helm release..."
helm upgrade --install loco helm/loco-chart -n "$NAMESPACE" -f "$VALUES" --wait --timeout 10m >>"$LOG" 2>&1

log "Waiting for emulator pods to be Ready..."
kubectl rollout status statefulset/loco-loco-emulator -n "$NAMESPACE" --timeout=15m >>"$LOG" 2>&1

PODS=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=emulator -o name)
log "Emulator pods: $(echo "$PODS" | tr '\n' ' ')"

# ---------------------------------------------------------------------------
# 4. Dashboard access + optional progressive-loading recording
# ---------------------------------------------------------------------------
log "Port-forwarding frontend to http://localhost:3000 (background)..."
pkill -f "port-forward.*loco-loco-frontend" 2>/dev/null || true
kubectl port-forward -n "$NAMESPACE" svc/loco-loco-frontend 3000:3000 >>"$LOG" 2>&1 &
PF_PID=$!
sleep 3

if [ "$RECORD" = true ]; then
  log "Recording progressive loading (playwright)..."
  node scripts/record-progressive-loading.js --url http://localhost:3000 --out "$PROOF_DIR" >>"$LOG" 2>&1 \
    && log "Dashboard recording saved to $PROOF_DIR" \
    || log "WARNING: dashboard recording failed (is playwright installed?)"
fi

# ---------------------------------------------------------------------------
# 5. In-game LAN session
# ---------------------------------------------------------------------------
if [ "$SKIP_GAME" != true ]; then
  log "Driving guests into a LAN game (QMP choreography)..."
  python3 scripts/lan-game-steps.py \
    --namespace "$NAMESPACE" \
    --proof-dir "$PROOF_DIR" \
    --host-steps scripts/lan-game-steps/host-create.steps \
    --guest-steps scripts/lan-game-steps/guest-join.steps 2>&1 | tee -a "$LOG"
fi

log ""
log "=== Done ==="
log "Dashboard:   http://localhost:3000 (port-forward pid $PF_PID)"
log "Proofs:      $PROOF_DIR"
log "Direct VNC:  kubectl port-forward -n $NAMESPACE loco-loco-emulator-0 5901:5901"
