#!/usr/bin/env bash
# Stop services started for E2E tests
set -euo pipefail
if [ -f /tmp/test_service_pids ]; then
  read BACKEND_PID STREAM_PID < /tmp/test_service_pids
  kill $BACKEND_PID $STREAM_PID >/dev/null 2>&1 || true
  rm -f /tmp/test_service_pids
  echo "Stopped test services"
fi
