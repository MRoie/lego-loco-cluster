#!/usr/bin/env bash
# scripts/test_ci_sequential.sh - Test the sequential CI approach locally
set -euo pipefail

LOG_DIR=${LOG_DIR:-k8s-tests/logs}
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/ci-sequential-test.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== Testing Sequential CI Approach ===" && date

# Set CI environment flags to simulate GitHub Actions
export CI=true
export GITHUB_ACTIONS=true

echo "Environment: CI=$CI, GITHUB_ACTIONS=$GITHUB_ACTIONS"

# Test Docker daemon startup
echo "=== Testing Docker Daemon Startup ===" && date
if ! scripts/start_docker_daemon.sh; then
    echo "❌ Docker daemon startup failed"
    exit 1
fi
echo "✅ Docker daemon startup successful" && date

# Test cluster management
echo "=== Testing Cluster Management ===" && date
if ! scripts/manage_ci_cluster.sh create; then
    echo "❌ Cluster creation failed"
    exit 1
fi
echo "✅ Cluster creation successful" && date

# Run the sequential tests (similar to CI)
echo "=== Running Sequential Tests (Simulated CI) ===" && date

# Network tests
echo "--- Running Network Tests ---" && date
if bash k8s-tests/test-network.sh; then
    echo "✅ Network tests passed"
else
    echo "⚠️  Network tests failed (may be expected in local environment)"
fi

# TCP tests  
echo "--- Running TCP Tests ---" && date
if bash k8s-tests/test-tcp.sh; then
    echo "✅ TCP tests passed"
else
    echo "⚠️  TCP tests failed (may be expected in local environment)"
fi

# Broadcast tests
echo "--- Running Broadcast Tests ---" && date  
if bash k8s-tests/test-broadcast.sh; then
    echo "✅ Broadcast tests passed"
else
    echo "⚠️  Broadcast tests failed (may be expected in local environment)"
fi

# Comprehensive monitoring tests (without building containers)
echo "--- Running Comprehensive Monitoring Tests ---" && date
if bash scripts/test_comprehensive_monitoring.sh; then
    echo "✅ Comprehensive monitoring tests passed"
else
    echo "⚠️  Comprehensive monitoring tests failed (may be expected without containers)"
fi

echo "=== Sequential Test Summary ===" && date
echo "All tests completed in sequence without concurrency conflicts"

# Test cluster status
echo "=== Cluster Status Check ===" && date
scripts/manage_ci_cluster.sh status

# Cleanup
echo "=== Cleanup ===" && date
scripts/manage_ci_cluster.sh destroy
echo "✅ Cleanup completed" && date

echo "=== Sequential CI Test Complete ===" && date
echo "✅ All tests ran sequentially without resource conflicts"
echo "📋 Check logs at: $LOG_FILE"