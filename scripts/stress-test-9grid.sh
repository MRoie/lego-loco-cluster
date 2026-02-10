#!/usr/bin/env bash
# ============================================================================
# 3×3 Multi-Instance Stress Test
# ============================================================================
# Launches the full 9-emulator grid and benchmarks for an extended period.
# Monitors for memory leaks, CPU creep, GStreamer stalls, WebSocket
# disconnects, and OOM kills.
#
# Usage:
#   ./scripts/stress-test-9grid.sh [--duration 1800] [--mode k8s|docker]
# ============================================================================
set -euo pipefail

DURATION=${1:-1800}   # Default 30 minutes
MODE=${2:-k8s}
NAMESPACE=${NAMESPACE:-loco}
REPLICAS=9
INTERVAL=30
OUTPUT_DIR="benchmark/stress-test-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$OUTPUT_DIR"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$OUTPUT_DIR/stress-test.log"
}

log "============================================================"
log " Lego Loco 3×3 Stress Test"
log " Duration: ${DURATION}s  Mode: $MODE  Replicas: $REPLICAS"
log "============================================================"

# ---------------------------------------------------------------
# Step 1: Scale to 9 instances
# ---------------------------------------------------------------
log "Scaling to $REPLICAS replicas ..."
if [ "$MODE" = "k8s" ]; then
  kubectl scale statefulset -n "$NAMESPACE" --all --replicas="$REPLICAS" 2>/dev/null || true
  kubectl rollout status statefulset -n "$NAMESPACE" --timeout=600s 2>/dev/null || true
elif [ "$MODE" = "docker" ]; then
  REPLICAS=$REPLICAS docker compose -f compose/docker-compose.yml up -d 2>/dev/null || true
fi

# Wait for stabilisation
log "Waiting 60s for instances to stabilise ..."
sleep 60

# ---------------------------------------------------------------
# Step 2: Baseline measurement
# ---------------------------------------------------------------
log "Taking baseline measurement ..."
python3 benchmark/bench.py \
  --mode "$MODE" \
  --replicas "$REPLICAS" \
  --skip-scale \
  --duration 30 \
  --interval 5 \
  --output-dir "$OUTPUT_DIR" \
  --csv "baseline.csv" 2>&1 | tee -a "$OUTPUT_DIR/stress-test.log"

# ---------------------------------------------------------------
# Step 3: Extended monitoring loop
# ---------------------------------------------------------------
log "Starting extended monitoring for ${DURATION}s ..."

RESOURCE_CSV="$OUTPUT_DIR/resource-timeseries.csv"
echo "timestamp,instance,cpu_pct,mem_mb,fps,status" > "$RESOURCE_CSV"

if [ "$MODE" = "k8s" ]; then
  PODS=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=emulator \
    -o jsonpath='{range .items[*]}{.metadata.name},{.status.podIP}{"\n"}{end}' 2>/dev/null || echo "")
else
  PODS=""
  for i in $(seq 0 $((REPLICAS - 1))); do
    PODS="${PODS}emulator-${i},localhost\n"
  done
fi

START_TIME=$(date +%s)
SAMPLE=0

while true; do
  ELAPSED=$(( $(date +%s) - START_TIME ))
  if [ "$ELAPSED" -ge "$DURATION" ]; then
    break
  fi

  REMAINING=$((DURATION - ELAPSED))
  log "Sample $SAMPLE — ${ELAPSED}s elapsed, ${REMAINING}s remaining"

  # Probe each instance health endpoint
  echo "$PODS" | while IFS=, read -r pod_name pod_ip; do
    [ -z "$pod_name" ] && continue
    HEALTH_PORT=8080

    HEALTH_JSON=$(curl -s --max-time 5 "http://${pod_ip}:${HEALTH_PORT}/health" 2>/dev/null || echo '{}')
    FPS=$(echo "$HEALTH_JSON" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('video',{}).get('estimated_frame_rate',0))" 2>/dev/null || echo 0)
    CPU=$(echo "$HEALTH_JSON" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('system_performance',{}).get('cpu_usage_percent',0))" 2>/dev/null || echo 0)
    MEM=$(echo "$HEALTH_JSON" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('system_performance',{}).get('qemu_memory_mb',0))" 2>/dev/null || echo 0)
    STATUS=$(echo "$HEALTH_JSON" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('overall_status','unknown'))" 2>/dev/null || echo "unreachable")

    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ),$pod_name,$CPU,$MEM,$FPS,$STATUS" >> "$RESOURCE_CSV"
  done

  # Check for OOM kills (K8s mode)
  if [ "$MODE" = "k8s" ]; then
    OOM_PODS=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name},{.status.containerStatuses[0].lastState.terminated.reason}{"\n"}{end}' 2>/dev/null | grep -i "oom" || true)
    if [ -n "$OOM_PODS" ]; then
      log "⚠️  OOM kills detected: $OOM_PODS"
    fi
  fi

  SAMPLE=$((SAMPLE + 1))
  sleep "$INTERVAL"
done

# ---------------------------------------------------------------
# Step 4: Final measurement
# ---------------------------------------------------------------
log "Taking final measurement ..."
python3 benchmark/bench.py \
  --mode "$MODE" \
  --replicas "$REPLICAS" \
  --skip-scale \
  --duration 30 \
  --interval 5 \
  --output-dir "$OUTPUT_DIR" \
  --csv "final.csv" 2>&1 | tee -a "$OUTPUT_DIR/stress-test.log"

# ---------------------------------------------------------------
# Step 5: Degradation analysis
# ---------------------------------------------------------------
log "Analysing degradation ..."

python3 - "$OUTPUT_DIR" << 'PYEOF'
import csv, sys, os
from pathlib import Path

output_dir = sys.argv[1]

def load_csv(path):
    if not os.path.exists(path):
        return []
    with open(path) as f:
        return list(csv.DictReader(f))

baseline = load_csv(os.path.join(output_dir, "baseline.csv"))
final = load_csv(os.path.join(output_dir, "final.csv"))
timeseries = load_csv(os.path.join(output_dir, "resource-timeseries.csv"))

lines = [
    "# 3×3 Stress Test Report",
    "",
    f"**Duration**: {len(timeseries)} samples",
    "",
]

if baseline and final:
    lines.append("## Baseline vs Final Comparison")
    lines.append("")
    lines.append("| Metric | Baseline | Final | Δ |")
    lines.append("|--------|----------|-------|---|")

    for metric in ["avg_fps", "avg_cpu_pct", "avg_latency_ms"]:
        b_vals = [float(r.get(metric, 0)) for r in baseline if r.get(metric)]
        f_vals = [float(r.get(metric, 0)) for r in final if r.get(metric)]
        if b_vals and f_vals:
            b_avg = sum(b_vals)/len(b_vals)
            f_avg = sum(f_vals)/len(f_vals)
            delta_pct = ((f_avg - b_avg) / b_avg * 100) if b_avg else 0
            flag = "⚠️" if abs(delta_pct) > 10 else "✅"
            lines.append(f"| {metric} | {b_avg:.1f} | {f_avg:.1f} | {delta_pct:+.1f}% {flag} |")

    lines.append("")

# Check for degradation > 10%
if timeseries:
    # Split into first and last quarter
    n = len(timeseries)
    first_q = timeseries[:n//4]
    last_q = timeseries[-n//4:]

    for metric in ["cpu_pct", "mem_mb", "fps"]:
        first_vals = [float(r.get(metric, 0)) for r in first_q if r.get(metric)]
        last_vals = [float(r.get(metric, 0)) for r in last_q if r.get(metric)]
        if first_vals and last_vals:
            first_avg = sum(first_vals)/len(first_vals)
            last_avg = sum(last_vals)/len(last_vals)
            if first_avg > 0:
                delta = (last_avg - first_avg) / first_avg * 100
                if abs(delta) > 10:
                    lines.append(f"⚠️  **{metric}** degraded by {delta:+.1f}% (first quarter: {first_avg:.1f}, last: {last_avg:.1f})")

lines.append("")
lines.append("## Conclusion")
lines.append("")
lines.append("See `resource-timeseries.csv` for full time-series data.")

Path(os.path.join(output_dir, "STRESS_TEST_REPORT.md")).write_text("\n".join(lines))
print(f"Report: {output_dir}/STRESS_TEST_REPORT.md")
PYEOF

log ""
log "============================================================"
log " Stress test complete. Results in $OUTPUT_DIR/"
log "============================================================"
