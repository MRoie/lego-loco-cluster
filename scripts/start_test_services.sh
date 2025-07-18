#!/usr/bin/env bash
# Start backend and mock stream server for E2E tests
echo "Starting backend and mock stream server"
set -euo pipefail

# Ensure dependencies are installed and frontend is built
if [ ! -d backend/node_modules ]; then
  (cd backend && npm install)
fi
if [ ! -d frontend/node_modules ]; then
  (cd frontend && npm install)
fi
if [ ! -f frontend/dist/index.html ]; then
  (cd frontend && npm run build)
fi

node backend/server.js &
BACKEND_PID=$!
node scripts/mock-stream-server.js &
STREAM_PID=$!
sleep 2
echo "$BACKEND_PID $STREAM_PID" > /tmp/test_service_pids
echo "Backend PID $BACKEND_PID, Stream PID $STREAM_PID"
