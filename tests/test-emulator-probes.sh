#!/bin/bash

# Emulator Kubernetes Probes Test Suite
# Tests the enhanced probe configuration for emulator pods

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

print_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

print_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

print_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}

print_info() {
    echo -e "${PURPLE}[INFO]${NC} $1"
}

# Test counter
TESTS_RUN=0
TESTS_PASSED=0

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    print_test "$test_name"
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if eval "$test_command"; then
        print_pass "$test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        print_fail "$test_name"
        return 1
    fi
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🧪 Emulator Kubernetes Probes Test Suite"
echo "========================================"
echo ""

# Test 1: Helm template validation
test_helm_template() {
    cd "$REPO_ROOT"
    
    # Check if helm is available
    if ! command -v helm &> /dev/null; then
        echo "❌ Helm not found, skipping template validation"
        return 1
    fi
    
    # Test that the template renders without errors
    helm template test-release helm/loco-chart/ --dry-run > /tmp/rendered-template.yaml 2>&1
    
    # Check if the template contains our probe configuration
    if grep -q "startupProbe:" /tmp/rendered-template.yaml && \
       grep -q "livenessProbe:" /tmp/rendered-template.yaml && \
       grep -q "readinessProbe:" /tmp/rendered-template.yaml; then
        return 0
    else
        echo "❌ Probe configuration not found in rendered template"
        return 1
    fi
}

# Test 2: Values validation
test_values_validation() {
    cd "$REPO_ROOT"
    
    # Check if probe configuration exists in values.yaml
    if grep -q "healthPort:" helm/loco-chart/values.yaml && \
       grep -q "probes:" helm/loco-chart/values.yaml && \
       grep -q "startup:" helm/loco-chart/values.yaml && \
       grep -q "liveness:" helm/loco-chart/values.yaml && \
       grep -q "readiness:" helm/loco-chart/values.yaml; then
        return 0
    else
        echo "❌ Probe configuration not found in values.yaml"
        return 1
    fi
}

# Test 3: StatefulSet probe configuration
test_statefulset_probe_config() {
    cd "$REPO_ROOT"
    
    # Check if probe configuration exists in StatefulSet template
    if grep -q "startupProbe:" helm/loco-chart/templates/emulator-statefulset.yaml && \
       grep -q "livenessProbe:" helm/loco-chart/templates/emulator-statefulset.yaml && \
       grep -q "readinessProbe:" helm/loco-chart/templates/emulator-statefulset.yaml && \
       grep -q "healthPort" helm/loco-chart/templates/emulator-statefulset.yaml; then
        return 0
    else
        echo "❌ Probe configuration not found in StatefulSet template"
        return 1
    fi
}

# Test 4: Probe endpoint path validation
test_probe_endpoint_path() {
    cd "$REPO_ROOT"
    
    # Check if helm is available
    if ! command -v helm &> /dev/null; then
        echo "❌ Helm not found, skipping endpoint validation"
        return 1
    fi
    
    # Render the template and check that health port and paths are correctly set
    helm template test-release helm/loco-chart/ --dry-run > /tmp/rendered-template.yaml 2>&1
    
    if grep -q "port: 8080" /tmp/rendered-template.yaml && \
       grep -q "path: /" /tmp/rendered-template.yaml; then
        return 0
    else
        echo "❌ Health port or path not correctly configured"
        return 1
    fi
}

# Test 5: Probe timing configuration validation
test_probe_timing_config() {
    cd "$REPO_ROOT"
    
    # Check if helm is available
    if ! command -v helm &> /dev/null; then
        echo "❌ Helm not found, skipping timing validation"
        return 1
    fi
    
    # Render the template and check timing configurations
    helm template test-release helm/loco-chart/ --dry-run > /tmp/rendered-template.yaml 2>&1
    
    # Validate that startup probe has higher failure threshold (emulator takes longer to start)
    if grep -A 10 "startupProbe:" /tmp/rendered-template.yaml | grep -q "failureThreshold: 30" && \
       grep -A 10 "livenessProbe:" /tmp/rendered-template.yaml | grep -q "periodSeconds: 15" && \
       grep -A 10 "readinessProbe:" /tmp/rendered-template.yaml | grep -q "periodSeconds: 10"; then
        return 0
    else
        echo "❌ Probe timing configuration not correct"
        return 1
    fi
}

# Run all tests
print_info "Starting probe configuration tests..."
echo ""

run_test "Values.yaml probe configuration validation" "test_values_validation"
run_test "StatefulSet probe template validation" "test_statefulset_probe_config"
run_test "Helm template rendering validation" "test_helm_template"
run_test "Probe endpoint path validation" "test_probe_endpoint_path"
run_test "Probe timing configuration validation" "test_probe_timing_config"

# Clean up
rm -f /tmp/rendered-template.yaml

# Summary
echo ""
echo "========================================"
echo "📊 Test Summary:"
echo "   Tests run: $TESTS_RUN"
echo "   Tests passed: $TESTS_PASSED"
echo "   Tests failed: $((TESTS_RUN - TESTS_PASSED))"

if [ $TESTS_PASSED -eq $TESTS_RUN ]; then
    print_pass "All tests passed! ✅"
    exit 0
else
    print_fail "Some tests failed! ❌"
    exit 1
fi