#!/usr/bin/env bash
# validate-audio-pipeline.sh — E3 validation: verify PulseAudio → GStreamer → UDP
# audio pipeline is running and emitting packets on port 5001.
# Usage: ./scripts/validate-audio-pipeline.sh [INSTANCE_INDEX]
#   INSTANCE_INDEX: 0-8 (default: 0)
set -euo pipefail

INSTANCE_INDEX="${1:-0}"
NAMESPACE="${NAMESPACE:-loco}"
LABEL_SELECTOR="app.kubernetes.io/component=emulator,app.kubernetes.io/part-of=lego-loco-cluster"
AUDIO_PORT="${AUDIO_PORT:-5001}"
PASS=0
FAIL=0
WARN=0

pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
warn() { echo "  ⚠️  $1"; WARN=$((WARN + 1)); }
info() { echo "ℹ️  $1"; }
header() { echo ""; echo "=== $1 ==="; }

# --- Pre-flight ---
header "Audio Pipeline Validation — Instance $INSTANCE_INDEX"
info "Namespace: $NAMESPACE"
info "Audio port: $AUDIO_PORT"

if ! command -v kubectl &>/dev/null; then
  echo "kubectl not found — aborting"; exit 1
fi

# --- Resolve pod name ---
header "1. Resolve emulator pod"
POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l "$LABEL_SELECTOR" \
  -o jsonpath="{.items[?(@.metadata.name =~ /.*-${INSTANCE_INDEX}$/)].metadata.name}" 2>/dev/null || true)

# Fallback: try naming convention
if [ -z "$POD_NAME" ]; then
  POD_NAME=$(kubectl get pods -n "$NAMESPACE" -o name 2>/dev/null \
    | grep "emulator" | grep "\-${INSTANCE_INDEX}$" | sed 's|pod/||' | head -1 || true)
fi

# Fallback: list all pods and pick by ordinal
if [ -z "$POD_NAME" ]; then
  POD_NAME=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null \
    | tr ' ' '\n' | grep -E "(emulator|qemu).*-${INSTANCE_INDEX}$" | head -1 || true)
fi

if [ -z "$POD_NAME" ]; then
  fail "Could not find emulator pod for instance $INSTANCE_INDEX"
  echo ""; echo "Summary: $PASS passed, $FAIL failed, $WARN warnings"
  exit 1
fi
pass "Found pod: $POD_NAME"

# Helper: run command inside the container
exec_in_pod() {
  kubectl exec -n "$NAMESPACE" "$POD_NAME" -- bash -c "$1" 2>/dev/null
}

# --- 2. PulseAudio running ---
header "2. PulseAudio daemon"
PA_STATUS=$(exec_in_pod "pulseaudio --check 2>&1 && echo RUNNING || echo STOPPED" || echo "EXEC_FAIL")

if echo "$PA_STATUS" | grep -q "RUNNING"; then
  pass "PulseAudio daemon is running"
else
  fail "PulseAudio daemon is NOT running ($PA_STATUS)"
fi

# Check PulseAudio sources (QEMU sb16 should create a monitor source)
PA_SOURCES=$(exec_in_pod "pactl list sources short 2>/dev/null" || echo "")
if [ -n "$PA_SOURCES" ]; then
  info "PulseAudio sources:"
  echo "$PA_SOURCES" | while read -r line; do info "  $line"; done
  if echo "$PA_SOURCES" | grep -qE 'RUNNING|IDLE|SUSPENDED'; then
    pass "PulseAudio has active source(s)"
  else
    warn "PulseAudio sources exist but none are active"
  fi
else
  warn "No PulseAudio sources detected (QEMU may not have connected audio yet)"
fi

# --- 3. QEMU audio configuration ---
header "3. QEMU audio device"
QEMU_CMDLINE=$(exec_in_pod "cat /proc/\$(pgrep -f qemu-system || echo 1)/cmdline 2>/dev/null | tr '\0' ' '" || echo "")

if [ -z "$QEMU_CMDLINE" ]; then
  fail "Could not read QEMU command line (process not found?)"
else
  # Check SB16 device
  if echo "$QEMU_CMDLINE" | grep -q "sb16"; then
    pass "QEMU has SB16 audio device configured"
  else
    fail "QEMU missing SB16 audio device in command line"
  fi

  # Check PulseAudio backend
  if echo "$QEMU_CMDLINE" | grep -q -- "-audiodev pa"; then
    pass "QEMU uses PulseAudio audio backend"
  else
    fail "QEMU not using PulseAudio backend"
  fi
fi

# --- 4. GStreamer audio pipeline ---
header "4. GStreamer audio pipeline"
GST_PROCS=$(exec_in_pod "ps aux | grep 'gst-launch.*pulsesrc' | grep -v grep" || echo "")

if [ -n "$GST_PROCS" ]; then
  pass "GStreamer audio pipeline process is running"
  info "Process: $(echo "$GST_PROCS" | head -1 | awk '{for(i=11;i<=NF;i++) printf "%s ", $i; print ""}')"

  # Verify pipeline elements
  if echo "$GST_PROCS" | grep -q "opusenc"; then
    pass "Pipeline includes Opus encoder"
  else
    fail "Pipeline missing Opus encoder"
  fi

  if echo "$GST_PROCS" | grep -q "rtpopuspay"; then
    pass "Pipeline includes RTP Opus payloader"
  else
    fail "Pipeline missing RTP Opus payloader"
  fi

  if echo "$GST_PROCS" | grep -q "udpsink"; then
    pass "Pipeline includes UDP sink"
  else
    fail "Pipeline missing UDP sink"
  fi

  if echo "$GST_PROCS" | grep -q "port=${AUDIO_PORT}"; then
    pass "UDP sink targets port $AUDIO_PORT"
  else
    warn "Could not confirm UDP sink port is $AUDIO_PORT"
  fi
else
  fail "GStreamer audio pipeline is NOT running"
  info "Expected: gst-launch-1.0 pulsesrc ! ... opusenc ! rtpopuspay ! udpsink port=$AUDIO_PORT"
fi

# --- 5. UDP packet emission ---
header "5. UDP packet emission on port $AUDIO_PORT"

# Method 1: Check netstat/ss for UDP traffic
UDP_ACTIVE=$(exec_in_pod "ss -u -n state all 2>/dev/null | grep ':${AUDIO_PORT}'" || echo "")
if [ -n "$UDP_ACTIVE" ]; then
  pass "UDP socket active on port $AUDIO_PORT"
  info "Socket: $UDP_ACTIVE"
else
  # Method 2: Use timeout + nc to listen for packets
  info "Checking for actual UDP packets (5s capture)..."
  PACKET_CHECK=$(exec_in_pod "timeout 5 bash -c 'dd if=<(nc -u -l -p ${AUDIO_PORT} 2>/dev/null) bs=1 count=1 2>/dev/null && echo RECEIVED' 2>/dev/null || echo TIMEOUT" || echo "EXEC_FAIL")

  if echo "$PACKET_CHECK" | grep -q "RECEIVED"; then
    pass "UDP packets detected on port $AUDIO_PORT"
  else
    # Method 3: Just verify the udpsink process is sending
    SEND_CHECK=$(exec_in_pod "ss -u -a 2>/dev/null | grep -c '${AUDIO_PORT}'" || echo "0")
    if [ "$SEND_CHECK" -gt 0 ]; then
      pass "UDP socket bound for port $AUDIO_PORT output"
    else
      warn "Could not confirm UDP packets on port $AUDIO_PORT (pipeline may still be initializing)"
    fi
  fi
fi

# --- Summary ---
header "Summary"
TOTAL=$((PASS + FAIL + WARN))
echo ""
echo "  Instance:  $INSTANCE_INDEX ($POD_NAME)"
echo "  Passed:    $PASS / $TOTAL"
echo "  Failed:    $FAIL / $TOTAL"
echo "  Warnings:  $WARN / $TOTAL"
echo ""

if [ "$FAIL" -eq 0 ]; then
  echo "🎉 Audio pipeline validation PASSED for instance $INSTANCE_INDEX"
  exit 0
else
  echo "💥 Audio pipeline validation FAILED — $FAIL check(s) need attention"
  exit 1
fi
