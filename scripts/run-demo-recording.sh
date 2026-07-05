#!/usr/bin/env bash
# ==========================================================================
# Lego Loco Cluster — Full Demo Recording Session
# ==========================================================================
# Orchestrates: 9 emulators + LAN networking + live benchmarks + video recording
#
# Prerequisites:
#   - Kind cluster 'loco' running with 9 emulator pods
#   - Backend and frontend deployed with v2 images
#   - Node.js + Playwright installed locally
#
# Usage:
#   ./scripts/run-demo-recording.sh
#   ./scripts/run-demo-recording.sh --skip-wait    # Skip waiting for all pods
#   ./scripts/run-demo-recording.sh --headless      # Headless recording only
# ==========================================================================
set -euo pipefail

SKIP_WAIT=false
HEADLESS=false
RECORDING_DURATION=120
BENCHMARK_DURATION=60

while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-wait) SKIP_WAIT=true; shift ;;
    --headless)  HEADLESS=true; shift ;;
    --duration)  RECORDING_DURATION=$2; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

echo "=============================================="
echo "  Lego Loco Cluster — Demo Recording Session"
echo "  $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
echo "=============================================="

# Step 1: Verify cluster
echo ""
echo "Step 1: Verifying cluster..."
READY_COUNT=$(MSYS_NO_PATHCONV=1 kubectl get pods -n loco -l app.kubernetes.io/component=emulator --no-headers 2>/dev/null | grep "1/1" | wc -l)
TOTAL_COUNT=$(MSYS_NO_PATHCONV=1 kubectl get pods -n loco -l app.kubernetes.io/component=emulator --no-headers 2>/dev/null | wc -l)
echo "  Emulators: $READY_COUNT/$TOTAL_COUNT ready"

if [ "$SKIP_WAIT" = false ] && [ "$READY_COUNT" -lt 9 ]; then
  echo "  Waiting for all 9 emulators to be ready..."
  echo "  (This can take 15-20 minutes for StatefulSet sequential rollout)"
  
  TIMEOUT=1200  # 20 minutes
  START_TIME=$(date +%s)
  while true; do
    READY_COUNT=$(MSYS_NO_PATHCONV=1 kubectl get pods -n loco -l app.kubernetes.io/component=emulator --no-headers 2>/dev/null | grep "1/1" | wc -l)
    TOTAL_COUNT=$(MSYS_NO_PATHCONV=1 kubectl get pods -n loco -l app.kubernetes.io/component=emulator --no-headers 2>/dev/null | wc -l)
    ELAPSED=$(( $(date +%s) - START_TIME ))
    
    echo "  [$ELAPSED s] Emulators: $READY_COUNT/$TOTAL_COUNT ready"
    
    if [ "$READY_COUNT" -ge 9 ]; then
      echo "  ✅ All 9 emulators ready!"
      break
    fi
    
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
      echo "  ⚠️  Timeout waiting for emulators. Proceeding with $READY_COUNT..."
      break
    fi
    
    sleep 30
  done
fi

# Step 2: Verify backend API (via NodePort)
echo ""
echo "Step 2: Verifying backend API..."
# Try NodePort first (Kind maps 30001->3001), fall back to port-forward
PF_BACKEND_PID=""
if curl -sf http://localhost:3001/health > /dev/null 2>&1; then
  echo "  ✅ Backend healthy (via NodePort)"
else
  echo "  Trying port-forward..."
  MSYS_NO_PATHCONV=1 kubectl port-forward -n loco svc/loco-loco-backend 3001:3001 &
  PF_BACKEND_PID=$!
  sleep 3
  if curl -sf http://localhost:3001/health > /dev/null 2>&1; then
    echo "  ✅ Backend healthy (via port-forward)"
  else
    echo "  ⚠️  Backend not responding on localhost:3001"
  fi
fi

# Check benchmark endpoint
BENCH_RESULT=$(curl -sf http://localhost:3001/api/benchmark/live 2>/dev/null || echo '{"error":"failed"}')
HEALTHY_COUNT=$(echo "$BENCH_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('summary',{}).get('healthyCount',0))" 2>/dev/null || echo "?")
echo "  Benchmark API: $HEALTHY_COUNT instances reporting"

# Step 3: Port-forward frontend (or use NodePort)
echo ""
echo "Step 3: Setting up frontend access..."
PF_FRONTEND_PID=""
if curl -sf http://localhost:3000 > /dev/null 2>&1; then
  echo "  ✅ Frontend accessible at http://localhost:3000 (via NodePort)"
else
  MSYS_NO_PATHCONV=1 kubectl port-forward -n loco svc/loco-loco-frontend 3000:3000 &
  PF_FRONTEND_PID=$!
  sleep 3
  if curl -sf http://localhost:3000 > /dev/null 2>&1; then
    echo "  ✅ Frontend accessible at http://localhost:3000 (via port-forward)"
  else
    echo "  ⚠️  Frontend not responding"
  fi
fi

# Step 4: Run benchmark (via API endpoint)
echo ""
echo "Step 4: Running benchmark ($BENCHMARK_DURATION s) via /api/benchmark/live..."
BENCH_OUTPUT_DIR="./benchmark"
mkdir -p "$BENCH_OUTPUT_DIR"

# Collect benchmark samples via API
echo "  Collecting samples for ${BENCHMARK_DURATION}s..."
{
  echo "timestamp,healthyCount,totalCount,avgFps,avgLatency,avgCpu,avgMemory"
  SAMPLES=$((BENCHMARK_DURATION / 5))
  for i in $(seq 1 "$SAMPLES"); do
    RESULT=$(curl -sf http://localhost:3001/api/benchmark/live 2>/dev/null || echo '{}')
    TS=$(echo "$RESULT" | grep -o '"timestamp":"[^"]*"' | head -1 | cut -d'"' -f4)
    HC=$(echo "$RESULT" | grep -o '"healthyCount":[0-9]*' | head -1 | cut -d: -f2)
    TC=$(echo "$RESULT" | grep -o '"totalCount":[0-9]*' | head -1 | cut -d: -f2)
    FPS=$(echo "$RESULT" | grep -o '"avgFps":[0-9]*' | head -1 | cut -d: -f2)
    LAT=$(echo "$RESULT" | grep -o '"avgLatency":[0-9]*' | head -1 | cut -d: -f2)
    CPU=$(echo "$RESULT" | grep -o '"avgCpu":[0-9.]*' | head -1 | cut -d: -f2)
    MEM=$(echo "$RESULT" | grep -o '"avgMemory":[0-9.]*' | head -1 | cut -d: -f2)
    echo "$TS,$HC,$TC,$FPS,$LAT,$CPU,$MEM"
    sleep 5
  done
} > "$BENCH_OUTPUT_DIR/demo-results.csv" &
BENCH_PID=$!

# Step 5: Record video (or just screenshot)
echo ""
echo "Step 5: Recording session..."

if [ "$HEADLESS" = true ]; then
  npx playwright test tests/playwright/record-session.spec.js \
    --project chromium \
    --timeout 180000 \
    --reporter list 2>&1 || echo "  Playwright recording finished"
else
  echo "  Opening browser at http://localhost:3000"
  echo "  Dashboard shows live benchmark overlay + 3x3 emulator grid"
  echo "  Recording for $RECORDING_DURATION seconds..."
  
  npx playwright test tests/playwright/record-session.spec.js \
    --project chromium \
    --headed \
    --timeout 180000 \
    --reporter list 2>&1 || echo "  Playwright recording finished"
fi

# Step 6: Collect benchmark results
echo ""
echo "Step 6: Collecting results..."
wait $BENCH_PID 2>/dev/null || true

echo "  Benchmark CSV: benchmark/demo-results.csv"
echo "  Videos: test-results/ (Playwright output)"

# Cleanup port-forwards
[ -n "$PF_BACKEND_PID" ] && kill "$PF_BACKEND_PID" 2>/dev/null || true
[ -n "$PF_FRONTEND_PID" ] && kill "$PF_FRONTEND_PID" 2>/dev/null || true

echo ""
echo "=============================================="
echo "  Demo Recording Complete!"
echo "  Videos saved to: test-results/"
echo "  Benchmark: benchmark/DEMO_BENCHMARK_REPORT.md"
echo "=============================================="
