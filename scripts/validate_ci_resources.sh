#!/usr/bin/env bash
# scripts/validate_ci_resources.sh - Validate system resources for CI compatibility
set -euo pipefail

echo "=== CI Resource Validation ===" && date

# System information
echo "--- System Information ---"
echo "Hostname: $(hostname)"
echo "Kernel: $(uname -r)"
echo "Architecture: $(uname -m)"
echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'=' -f2 | tr -d '"')"

# CPU information
echo "--- CPU Information ---"
cpu_count=$(nproc)
echo "CPU Cores: $cpu_count"
echo "CPU Info: $(grep 'model name' /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs)"

# Memory information
echo "--- Memory Information ---"
total_memory_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
available_memory_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
total_memory_mb=$((total_memory_kb / 1024))
available_memory_mb=$((available_memory_kb / 1024))
echo "Total Memory: ${total_memory_mb}MB"
echo "Available Memory: ${available_memory_mb}MB"

# Disk information
echo "--- Disk Information ---"
echo "Disk usage:"
df -h /
echo "Disk space available: $(df -h / | awk 'NR==2 {print $4}')"

# Container environment detection
echo "--- Container Environment ---"
if [[ -n "${CI:-}" ]]; then
    echo "CI Environment: $CI"
fi
if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "GitHub Actions: $GITHUB_ACTIONS"
fi
if [[ -f /.dockerenv ]]; then
    echo "Running in Docker container: Yes"
else
    echo "Running in Docker container: No"
fi

# Resource requirements for CI
echo "--- CI Resource Requirements ---"
MIN_CPUS=2
MIN_MEMORY_MB=1900  # Updated to match minikube minimum
MIN_DISK_GB=8       # Updated to match cluster script

echo "Minimum Requirements:"
echo "  CPUs: $MIN_CPUS"
echo "  Memory: ${MIN_MEMORY_MB}MB"
echo "  Disk: ${MIN_DISK_GB}GB"

echo "Current Resources:"
echo "  CPUs: $cpu_count"
echo "  Memory: ${available_memory_mb}MB"

# Validation
echo "--- Resource Validation ---"
validation_passed=true

if [ "$cpu_count" -lt "$MIN_CPUS" ]; then
    echo "❌ CPU: Insufficient ($cpu_count < $MIN_CPUS)"
    validation_passed=false
else
    echo "✅ CPU: Sufficient ($cpu_count >= $MIN_CPUS)"
fi

if [ "$available_memory_mb" -lt "$MIN_MEMORY_MB" ]; then
    echo "❌ Memory: Insufficient (${available_memory_mb}MB < ${MIN_MEMORY_MB}MB)"
    validation_passed=false
else
    echo "✅ Memory: Sufficient (${available_memory_mb}MB >= ${MIN_MEMORY_MB}MB)"
fi

# Docker availability
echo "--- Docker Availability ---"
if command -v docker &> /dev/null; then
    echo "✅ Docker command available"
    if docker info >/dev/null 2>&1; then
        echo "✅ Docker daemon accessible"
        docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
        echo "Docker version: $docker_version"
    else
        echo "⚠️  Docker daemon not running"
    fi
else
    echo "❌ Docker command not available"
    validation_passed=false
fi

# Kubernetes tools
echo "--- Kubernetes Tools ---"
if command -v kubectl &> /dev/null; then
    echo "✅ kubectl available: $(kubectl version --client=true --short 2>/dev/null || echo 'unknown')"
else
    echo "❌ kubectl not available"
fi

if command -v helm &> /dev/null; then
    echo "✅ helm available: $(helm version --short 2>/dev/null || echo 'unknown')"
else
    echo "❌ helm not available"
fi

# Final validation result
echo "--- Final Validation ---"
if [ "$validation_passed" = true ]; then
    echo "✅ System meets CI requirements for cluster testing"
    exit 0
else
    echo "❌ System does not meet CI requirements"
    echo "⚠️  Some tests may fail due to resource constraints"
    exit 1
fi