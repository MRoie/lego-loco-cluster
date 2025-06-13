#!/usr/bin/env bash
# Start backend and mock stream server for E2E tests
echo "Starting backend and mock stream server" 
set -euo pipefail
node backend/server.js &
BACKEND_PID=$!
node scripts/mock-stream-server.js &
STREAM_PID=$!
# Wait a moment for services to start
sleep 2
echo "$BACKEND_PID $STREAM_PID" > /tmp/test_service_pids
echo "Backend PID $BACKEND_PID, Stream PID $STREAM_PID"
