#!/usr/bin/env bash

# Comprehensive test for QEMU Deep Health Monitoring and Recovery System
# Tests both container health monitoring and backend integration

set -euo pipefail

echo "🧪 Starting Comprehensive QEMU Health Monitoring Tests"
echo "======================================================"

# Test configuration
BACKEND_URL="http://localhost:3001"
TEST_INSTANCE="instance-0"
HEALTH_CONTAINER="loco-emulator-0"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

# Test function wrapper
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    echo ""
    log_info "Testing: $test_name"
    echo "----------------------------------------"
    
    if eval "$test_command"; then
        log_success "$test_name - PASSED"
        return 0
    else
        log_error "$test_name - FAILED"
        return 1
    fi
}

# Test 1: QEMU Health Monitor Script
test_health_monitor_script() {
    log_info "Testing health monitor script functionality..."
    
    # Test the script in test mode
    local script_path="./containers/qemu-softgpu/health-monitor.sh"
    
    if [ ! -f "$script_path" ]; then
        log_error "Health monitor script not found: $script_path"
        return 1
    fi
    
    # Test script execution
    if bash "$script_path" test 2>/dev/null; then
        log_success "Health monitor script executes correctly"
        return 0
    else
        log_error "Health monitor script failed to execute"
        return 1
    fi
}

# Test 2: Backend Quality API Endpoints
test_backend_api_endpoints() {
    log_info "Testing backend API endpoints..."
    
    # Test basic quality metrics endpoint
    if curl -s -f "$BACKEND_URL/api/quality/metrics" >/dev/null; then
        log_success "Basic quality metrics endpoint accessible"
    else
        log_error "Basic quality metrics endpoint not accessible"
        return 1
    fi
    
    # Test deep health endpoint
    if curl -s -f "$BACKEND_URL/api/quality/deep-health" >/dev/null; then
        log_success "Deep health endpoint accessible"
    else
        log_error "Deep health endpoint not accessible"
        return 1
    fi
    
    # Test instance-specific endpoints
    if curl -s -f "$BACKEND_URL/api/quality/metrics/$TEST_INSTANCE" >/dev/null; then
        log_success "Instance-specific metrics endpoint accessible"
    else
        log_error "Instance-specific metrics endpoint not accessible"
        return 1
    fi
    
    return 0
}

# Test 3: Deep Health Data Structure
test_deep_health_data() {
    log_info "Testing deep health data structure..."
    
    local response=$(curl -s "$BACKEND_URL/api/quality/deep-health")
    
    if echo "$response" | jq empty 2>/dev/null; then
        log_success "Deep health response is valid JSON"
    else
        log_error "Deep health response is not valid JSON"
        return 1
    fi
    
    # Check for required fields
    local required_fields=("timestamp" "overallStatus" "deepHealth")
    
    for field in "${required_fields[@]}"; do
        if echo "$response" | jq -e ".[\"$TEST_INSTANCE\"].$field" >/dev/null 2>&1; then
            log_success "Required field '$field' present in response"
        else
            log_info "Field '$field' not present (may be expected if instance not running)"
        fi
    done
    
    return 0
}

# Test 4: Recovery Mechanism
test_recovery_mechanism() {
    log_info "Testing recovery mechanism..."
    
    # Test recovery endpoint
    local recovery_response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d '{"forceRecovery": true}' \
        "$BACKEND_URL/api/quality/recover/$TEST_INSTANCE")
    
    if echo "$recovery_response" | jq -e '.message' >/dev/null 2>&1; then
        log_success "Recovery endpoint responds correctly"
        
        local message=$(echo "$recovery_response" | jq -r '.message')
        log_info "Recovery message: $message"
        
        return 0
    else
        log_error "Recovery endpoint not working correctly"
        return 1
    fi
}

# Test 5: Recovery Status Tracking
test_recovery_status() {
    log_info "Testing recovery status tracking..."
    
    local status_response=$(curl -s "$BACKEND_URL/api/quality/recovery-status")
    
    if echo "$status_response" | jq empty 2>/dev/null; then
        log_success "Recovery status endpoint responds with valid JSON"
        return 0
    else
        log_error "Recovery status endpoint not working"
        return 1
    fi
}

# Test 6: Failure Type Detection
test_failure_detection() {
    log_info "Testing failure type detection logic..."
    
    # This test checks if the backend correctly identifies different failure types
    local metrics_response=$(curl -s "$BACKEND_URL/api/quality/deep-health/$TEST_INSTANCE")
    
    if echo "$metrics_response" | jq empty 2>/dev/null; then
        local failure_type=$(echo "$metrics_response" | jq -r '.failureType // "none"')
        log_info "Current failure type: $failure_type"
        
        # Valid failure types
        local valid_types=("none" "network" "qemu" "client" "mixed")
        
        if printf '%s\n' "${valid_types[@]}" | grep -q "^$failure_type$"; then
            log_success "Failure type detection working correctly"
            return 0
        else
            log_error "Invalid failure type detected: $failure_type"
            return 1
        fi
    else
        log_info "No deep health data available for $TEST_INSTANCE (expected if not running)"
        return 0
    fi
}

# Test 7: Frontend Integration
test_frontend_integration() {
    log_info "Testing frontend integration..."
    
    # Check if QualityIndicator component exists
    local component_path="./frontend/src/components/QualityIndicator.jsx"
    
    if [ ! -f "$component_path" ]; then
        log_error "QualityIndicator component not found"
        return 1
    fi
    
    # Check if component includes deep health functionality
    if grep -q "deepHealth" "$component_path"; then
        log_success "QualityIndicator component includes deep health functionality"
    else
        log_error "QualityIndicator component missing deep health functionality"
        return 1
    fi
    
    # Check for recovery button functionality
    if grep -q "triggerRecovery" "$component_path"; then
        log_success "QualityIndicator component includes recovery functionality"
    else
        log_error "QualityIndicator component missing recovery functionality"
        return 1
    fi
    
    return 0
}

# Test 8: Container Configuration
test_container_configuration() {
    log_info "Testing container configuration..."
    
    # Check if Dockerfiles include health monitoring
    local dockerfiles=("./containers/qemu/Dockerfile" "./containers/qemu-softgpu/Dockerfile")
    
    for dockerfile in "${dockerfiles[@]}"; do
        if [ -f "$dockerfile" ]; then
            if grep -q "health-monitor.sh" "$dockerfile"; then
                log_success "$(basename $dockerfile) includes health monitor script"
            else
                log_error "$(basename $dockerfile) missing health monitor script"
                return 1
            fi
            
            if grep -q "EXPOSE 8080" "$dockerfile"; then
                log_success "$(basename $dockerfile) exposes health port"
            else
                log_error "$(basename $dockerfile) missing health port exposure"
                return 1
            fi
        else
            log_error "Dockerfile not found: $dockerfile"
            return 1
        fi
    done
    
    return 0
}

# Test 9: Helm Chart Integration
test_helm_integration() {
    log_info "Testing Helm chart integration..."
    
    local service_file="./helm/loco-chart/templates/emulator-service.yaml"
    local statefulset_file="./helm/loco-chart/templates/emulator-statefulset.yaml"
    
    # Check service includes health port
    if [ -f "$service_file" ]; then
        if grep -q "name: health" "$service_file" && grep -q "port: 8080" "$service_file"; then
            log_success "Emulator service includes health port"
        else
            log_error "Emulator service missing health port configuration"
            return 1
        fi
    else
        log_error "Emulator service file not found"
        return 1
    fi
    
    # Check StatefulSet includes health port
    if [ -f "$statefulset_file" ]; then
        if grep -q "containerPort: 8080" "$statefulset_file"; then
            log_success "Emulator StatefulSet includes health port"
        else
            log_error "Emulator StatefulSet missing health port configuration"
            return 1
        fi
    else
        log_error "Emulator StatefulSet file not found"
        return 1
    fi
    
    return 0
}

# Test 10: Configuration Updates
test_configuration_updates() {
    log_info "Testing configuration updates..."
    
    local instances_file="./config/instances.json"
    
    if [ -f "$instances_file" ]; then
        if grep -q "healthUrl" "$instances_file"; then
            log_success "Instance configuration includes health URLs"
        else
            log_error "Instance configuration missing health URLs"
            return 1
        fi
    else
        log_error "Instances configuration file not found"
        return 1
    fi
    
    return 0
}

# Main test execution
main() {
    echo "Starting comprehensive health monitoring test suite..."
    echo ""
    
    local total_tests=0
    local passed_tests=0
    local failed_tests=0
    
    # List of all tests
    local tests=(
        "Health Monitor Script:test_health_monitor_script"
        "Backend API Endpoints:test_backend_api_endpoints"
        "Deep Health Data Structure:test_deep_health_data"
        "Recovery Mechanism:test_recovery_mechanism"
        "Recovery Status Tracking:test_recovery_status"
        "Failure Type Detection:test_failure_detection"
        "Frontend Integration:test_frontend_integration"
        "Container Configuration:test_container_configuration"
        "Helm Chart Integration:test_helm_integration"
        "Configuration Updates:test_configuration_updates"
    )
    
    # Run all tests
    for test in "${tests[@]}"; do
        local test_name="${test%%:*}"
        local test_function="${test##*:}"
        
        total_tests=$((total_tests + 1))
        
        if run_test "$test_name" "$test_function"; then
            passed_tests=$((passed_tests + 1))
        else
            failed_tests=$((failed_tests + 1))
        fi
    done
    
    # Summary
    echo ""
    echo "======================================================"
    echo "🏁 Test Summary"
    echo "======================================================"
    log_info "Total Tests: $total_tests"
    log_success "Passed: $passed_tests"
    
    if [ $failed_tests -gt 0 ]; then
        log_error "Failed: $failed_tests"
        echo ""
        log_error "Some tests failed. Please review the implementation."
        exit 1
    else
        echo ""
        log_success "All tests passed! QEMU deep health monitoring system is working correctly."
        exit 0
    fi
}

# Check dependencies
if ! command -v jq &> /dev/null; then
    log_error "jq is required for JSON processing. Please install it."
    exit 1
fi

if ! command -v curl &> /dev/null; then
    log_error "curl is required for API testing. Please install it."
    exit 1
fi

# Run main function
main "$@"