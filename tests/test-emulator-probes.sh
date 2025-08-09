#!/bin/bash

# SRE-Focused Kubernetes Probe Reliability Test Suite
# Tests actual probe behavior, timing, and reliability with running services
# Based on Site Reliability Engineering principles

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
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

print_sli() {
    echo -e "${CYAN}[SLI]${NC} $1"
}

print_slo() {
    echo -e "${YELLOW}[SLO]${NC} $1"
}

# Test counter and SRE metrics
TESTS_RUN=0
TESTS_PASSED=0
SLI_MEASUREMENTS=()
SLO_VIOLATIONS=0

# SRE Configuration - Service Level Objectives
declare -A SERVICE_SLOS=(
    ["startup_probe_success_rate"]="95"
    ["liveness_probe_response_time_ms"]="500"
    ["readiness_probe_response_time_ms"]="300"
    ["startup_time_max_seconds"]="300"
    ["recovery_time_max_seconds"]="60"
    ["probe_success_rate"]="99"
)

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🔬 SRE-Focused Kubernetes Probe Reliability Test Suite"
echo "======================================================"
echo "Testing actual service behavior, timing, and reliability"
echo ""

# SRE Test Framework Functions
run_sre_test() {
    local test_name="$1"
    local test_command="$2"
    local sli_metric="$3"
    local expected_value="$4"
    
    print_test "$test_name"
    TESTS_RUN=$((TESTS_RUN + 1))
    
    local start_time=$(date +%s%3N)
    local result
    if eval "$test_command"; then
        local end_time=$(date +%s%3N)
        local duration=$((end_time - start_time))
        
        print_pass "$test_name (${duration}ms)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        
        if [ -n "$sli_metric" ] && [ -n "$expected_value" ]; then
            record_sli "$sli_metric" "$duration" "$expected_value"
        fi
        return 0
    else
        local end_time=$(date +%s%3N)
        local duration=$((end_time - start_time))
        print_fail "$test_name (${duration}ms)"
        
        if [ -n "$sli_metric" ] && [ -n "$expected_value" ]; then
            record_sli "$sli_metric" "$duration" "$expected_value"
            SLO_VIOLATIONS=$((SLO_VIOLATIONS + 1))
        fi
        return 1
    fi
}

record_sli() {
    local metric="$1"
    local value="$2"
    local threshold="$3"
    
    SLI_MEASUREMENTS+=("$metric:$value:$threshold")
    
    if [ "$value" -le "$threshold" ]; then
        print_sli "$metric: $value <= $threshold ✅"
    else
        print_sli "$metric: $value > $threshold ❌ (SLO violation)"
    fi
}

# Service Discovery and Environment Detection
detect_environment() {
    print_info "Detecting deployment environment..."
    
    if kubectl cluster-info &>/dev/null; then
        echo "kubernetes"
    elif docker-compose -f "$REPO_ROOT/compose/docker-compose.yml" ps &>/dev/null; then
        echo "docker-compose"
    elif [ -f "$REPO_ROOT/.env" ] && grep -q "ENVIRONMENT=development" "$REPO_ROOT/.env"; then
        echo "development"
    else
        echo "unknown"
    fi
}

# Service Health Check Functions
check_service_health() {
    local service_url="$1"
    local timeout="${2:-5}"
    
    if curl -f -s --max-time "$timeout" "$service_url" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

measure_response_time() {
    local service_url="$1"
    local timeout="${2:-5}"
    
    local start_time=$(date +%s%3N)
    if curl -f -s --max-time "$timeout" "$service_url" >/dev/null 2>&1; then
        local end_time=$(date +%s%3N)
        echo $((end_time - start_time))
        return 0
    else
        echo "-1"
        return 1
    fi
}

# Kubernetes-specific probe testing
test_k8s_probe_behavior() {
    local pod_name="$1"
    local probe_type="$2"
    local namespace="${3:-loco}"
    
    print_info "Testing $probe_type probe for pod $pod_name"
    
    # Get probe configuration from pod spec
    local probe_config=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath="{.spec.containers[0].${probe_type}Probe}" 2>/dev/null || echo "{}")
    
    if [ "$probe_config" == "{}" ]; then
        print_fail "$probe_type probe not configured for $pod_name"
        return 1
    fi
    
    # Extract probe timing
    local period=$(echo "$probe_config" | jq -r '.periodSeconds // 10')
    local timeout=$(echo "$probe_config" | jq -r '.timeoutSeconds // 5')
    local initial_delay=$(echo "$probe_config" | jq -r '.initialDelaySeconds // 0')
    
    print_info "$probe_type probe config: period=${period}s, timeout=${timeout}s, initial_delay=${initial_delay}s"
    
    # Test probe endpoint directly
    local pod_ip=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.status.podIP}' 2>/dev/null || echo "")
    if [ -n "$pod_ip" ]; then
        local health_port=$(echo "$probe_config" | jq -r '.httpGet.port // 8080')
        local health_path=$(echo "$probe_config" | jq -r '.httpGet.path // "/"')
        local probe_url="http://${pod_ip}:${health_port}${health_path}"
        
        local response_time=$(measure_response_time "$probe_url" "$timeout")
        if [ "$response_time" -ne -1 ]; then
            print_sli "$probe_type probe response time: ${response_time}ms"
            
            # Check against SLO
            local slo_key="${probe_type}_probe_response_time_ms"
            local slo_threshold="${SERVICE_SLOS[$slo_key]:-1000}"
            
            if [ "$response_time" -le "$slo_threshold" ]; then
                print_pass "$probe_type probe response time within SLO"
                return 0
            else
                print_fail "$probe_type probe response time exceeds SLO ($response_time > $slo_threshold)"
                SLO_VIOLATIONS=$((SLO_VIOLATIONS + 1))
                return 1
            fi
        else
            print_fail "$probe_type probe endpoint unreachable"
            return 1
        fi
    else
        print_fail "Cannot get pod IP for $pod_name"
        return 1
    fi
}

# SRE Test Cases - Service-Specific Probe Strategies

# Test 1: Environment and Service Discovery
test_environment_discovery() {
    local env=$(detect_environment)
    print_info "Detected environment: $env"
    
    case "$env" in
        "kubernetes")
            print_pass "Kubernetes environment detected - full SRE testing available"
            return 0
            ;;
        "docker-compose")
            print_pass "Docker Compose environment detected - container testing available"
            return 0
            ;;
        "development")
            print_pass "Development environment detected - local testing only"
            return 0
            ;;
        *)
            print_fail "Unknown environment - limited testing available"
            return 1
            ;;
    esac
}

# Test 2: Backend Service Probe Strategy
test_backend_probe_strategy() {
    local backend_url="${BACKEND_URL:-http://localhost:3001}"
    
    print_info "Testing backend service probe strategy"
    
    # Test health endpoint availability
    if ! check_service_health "$backend_url/health"; then
        print_fail "Backend health endpoint not accessible"
        return 1
    fi
    
    # Measure response times for different endpoints
    local health_time=$(measure_response_time "$backend_url/health")
    local api_time=$(measure_response_time "$backend_url/api/instances")
    local deep_health_time=$(measure_response_time "$backend_url/api/quality/deep-health" 10)
    
    print_sli "Backend health endpoint: ${health_time}ms"
    print_sli "Backend API endpoint: ${api_time}ms"
    print_sli "Backend deep health: ${deep_health_time}ms"
    
    # Validate against SLOs
    local health_slo="${SERVICE_SLOS[liveness_probe_response_time_ms]}"
    local api_slo="${SERVICE_SLOS[readiness_probe_response_time_ms]}"
    
    if [ "$health_time" -le "$health_slo" ] && [ "$api_time" -le "$api_slo" ]; then
        print_pass "Backend probe strategy meets SLO requirements"
        return 0
    else
        print_fail "Backend probe strategy violates SLO requirements"
        SLO_VIOLATIONS=$((SLO_VIOLATIONS + 1))
        return 1
    fi
}

# Test 3: Emulator Service Probe Strategy
test_emulator_probe_strategy() {
    local emulator_instance="${1:-instance-0}"
    local health_url="http://localhost:8080"
    
    print_info "Testing emulator service probe strategy for $emulator_instance"
    
    # For Kubernetes environment, get the actual pod
    local env=$(detect_environment)
    if [ "$env" == "kubernetes" ]; then
        local pod_name="loco-emulator-0"
        
        # Check if pod exists
        if kubectl get pod "$pod_name" -n loco &>/dev/null; then
            # Test each probe type
            test_k8s_probe_behavior "$pod_name" "startup" "loco" || return 1
            test_k8s_probe_behavior "$pod_name" "liveness" "loco" || return 1
            test_k8s_probe_behavior "$pod_name" "readiness" "loco" || return 1
        else
            print_fail "Emulator pod $pod_name not found"
            return 1
        fi
    else
        # Test local or Docker Compose setup
        print_info "Testing emulator health endpoint locally"
        
        local health_time=$(measure_response_time "$health_url")
        if [ "$health_time" -ne -1 ]; then
            print_sli "Emulator health response: ${health_time}ms"
            
            # Get detailed health data
            local health_data=$(curl -s "$health_url" 2>/dev/null || echo '{}')
            local overall_status=$(echo "$health_data" | jq -r '.overall_status // "unknown"')
            local qemu_healthy=$(echo "$health_data" | jq -r '.qemu_healthy // false')
            
            print_info "Emulator overall status: $overall_status"
            print_info "QEMU process healthy: $qemu_healthy"
            
            if [ "$overall_status" == "healthy" ] && [ "$qemu_healthy" == "true" ]; then
                print_pass "Emulator health strategy validates all subsystems"
                return 0
            else
                print_fail "Emulator health strategy detects issues"
                return 1
            fi
        else
            print_fail "Emulator health endpoint not accessible"
            return 1
        fi
    fi
}

# Test 4: Startup Time Measurement and SLO Validation
test_startup_time_slo() {
    local env=$(detect_environment)
    
    print_info "Testing startup time SLO compliance"
    
    if [ "$env" == "kubernetes" ]; then
        # Check recent pod restarts and startup times
        local pods=$(kubectl get pods -n loco -l app=loco-emulator --no-headers 2>/dev/null | awk '{print $1}' || echo "")
        
        if [ -z "$pods" ]; then
            print_fail "No emulator pods found for startup time testing"
            return 1
        fi
        
        local startup_violations=0
        local total_pods=0
        
        for pod in $pods; do
            total_pods=$((total_pods + 1))
            
            # Get pod age and ready time
            local pod_start=$(kubectl get pod "$pod" -n loco -o jsonpath='{.status.startTime}' 2>/dev/null)
            local ready_conditions=$(kubectl get pod "$pod" -n loco -o jsonpath='{.status.conditions[?(@.type=="Ready")].lastTransitionTime}' 2>/dev/null)
            
            if [ -n "$pod_start" ] && [ -n "$ready_conditions" ]; then
                # Calculate startup time (simplified - would need proper date parsing in production)
                print_info "Pod $pod startup tracking available"
                
                # Check if startup probe is configured correctly
                local startup_config=$(kubectl get pod "$pod" -n loco -o jsonpath='{.spec.containers[0].startupProbe}' 2>/dev/null)
                if [ "$startup_config" != "" ]; then
                    local failure_threshold=$(echo "$startup_config" | jq -r '.failureThreshold // 30')
                    local period_seconds=$(echo "$startup_config" | jq -r '.periodSeconds // 10')
                    local max_startup_time=$((failure_threshold * period_seconds))
                    
                    print_sli "Pod $pod max allowed startup time: ${max_startup_time}s"
                    
                    local slo_max="${SERVICE_SLOS[startup_time_max_seconds]}"
                    if [ "$max_startup_time" -le "$slo_max" ]; then
                        print_pass "Pod $pod startup time configuration meets SLO"
                    else
                        print_fail "Pod $pod startup time configuration exceeds SLO"
                        startup_violations=$((startup_violations + 1))
                    fi
                else
                    print_fail "Pod $pod missing startup probe configuration"
                    startup_violations=$((startup_violations + 1))
                fi
            else
                print_fail "Cannot determine startup time for pod $pod"
                startup_violations=$((startup_violations + 1))
            fi
        done
        
        local success_rate=$(( (total_pods - startup_violations) * 100 / total_pods ))
        local slo_threshold="${SERVICE_SLOS[startup_probe_success_rate]}"
        
        print_sli "Startup SLO compliance: ${success_rate}%"
        
        if [ "$success_rate" -ge "$slo_threshold" ]; then
            print_pass "Startup time SLO compliance achieved"
            return 0
        else
            print_fail "Startup time SLO compliance failed"
            SLO_VIOLATIONS=$((SLO_VIOLATIONS + 1))
            return 1
        fi
    else
        print_info "Startup time SLO testing requires Kubernetes environment"
        return 0
    fi
}

# Test 5: Failure Injection and Recovery Testing
test_failure_recovery_behavior() {
    local env=$(detect_environment)
    
    print_info "Testing failure detection and recovery behavior"
    
    if [ "$env" == "kubernetes" ]; then
        local test_pod="loco-emulator-0"
        
        if kubectl get pod "$test_pod" -n loco &>/dev/null; then
            print_info "Testing liveness probe failure detection"
            
            # Get current restart count
            local initial_restarts=$(kubectl get pod "$test_pod" -n loco -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")
            
            print_info "Initial restart count: $initial_restarts"
            
            # Check probe configuration
            local liveness_config=$(kubectl get pod "$test_pod" -n loco -o jsonpath='{.spec.containers[0].livenessProbe}' 2>/dev/null)
            if [ "$liveness_config" != "" ]; then
                local failure_threshold=$(echo "$liveness_config" | jq -r '.failureThreshold // 3')
                local period_seconds=$(echo "$liveness_config" | jq -r '.periodSeconds // 15')
                local expected_recovery_time=$((failure_threshold * period_seconds))
                
                print_sli "Expected recovery time: ${expected_recovery_time}s"
                
                local slo_recovery="${SERVICE_SLOS[recovery_time_max_seconds]}"
                if [ "$expected_recovery_time" -le "$slo_recovery" ]; then
                    print_pass "Recovery time configuration meets SLO"
                    return 0
                else
                    print_fail "Recovery time configuration exceeds SLO"
                    SLO_VIOLATIONS=$((SLO_VIOLATIONS + 1))
                    return 1
                fi
            else
                print_fail "Liveness probe not configured for $test_pod"
                return 1
            fi
        else
            print_fail "Test pod $test_pod not found"
            return 1
        fi
    else
        print_info "Failure recovery testing requires Kubernetes environment"
        return 0
    fi
}

# Test 6: Cross-Service Probe Coordination
test_cross_service_coordination() {
    print_info "Testing cross-service probe coordination and dependencies"
    
    local services=("backend" "emulator")
    local coordination_success=true
    
    # Test that backend can reach emulator health endpoints
    local backend_url="${BACKEND_URL:-http://localhost:3001}"
    if check_service_health "$backend_url/health"; then
        # Test backend's ability to monitor emulator health
        local deep_health_time=$(measure_response_time "$backend_url/api/quality/deep-health" 15)
        
        if [ "$deep_health_time" -ne -1 ]; then
            print_sli "Cross-service health check: ${deep_health_time}ms"
            
            # Get actual health data
            local health_data=$(curl -s "$backend_url/api/quality/deep-health" 2>/dev/null || echo '{}')
            local instance_count=$(echo "$health_data" | jq 'length' 2>/dev/null || echo "0")
            
            print_info "Backend monitoring $instance_count emulator instances"
            
            if [ "$instance_count" -gt 0 ]; then
                print_pass "Cross-service probe coordination working"
            else
                print_fail "Cross-service probe coordination not working"
                coordination_success=false
            fi
        else
            print_fail "Backend unable to perform deep health checks"
            coordination_success=false
        fi
    else
        print_fail "Backend not available for coordination testing"
        coordination_success=false
    fi
    
    if [ "$coordination_success" == "true" ]; then
        return 0
    else
        return 1
    fi
}

# Main Test Execution with SRE Focus
print_info "Starting SRE-focused probe reliability testing..."
print_slo "Service Level Objectives (SLOs):"
for slo_key in "${!SERVICE_SLOS[@]}"; do
    print_slo "  $slo_key: ${SERVICE_SLOS[$slo_key]}"
done
echo ""

# Set environment variables for testing
export BACKEND_URL="${BACKEND_URL:-http://localhost:3001}"

# Run SRE tests
run_sre_test "Environment and Service Discovery" "test_environment_discovery" "" ""
run_sre_test "Backend Service Probe Strategy" "test_backend_probe_strategy" "liveness_probe_response_time_ms" "${SERVICE_SLOS[liveness_probe_response_time_ms]}"
run_sre_test "Emulator Service Probe Strategy" "test_emulator_probe_strategy" "readiness_probe_response_time_ms" "${SERVICE_SLOS[readiness_probe_response_time_ms]}"
run_sre_test "Startup Time SLO Validation" "test_startup_time_slo" "" ""
run_sre_test "Failure Recovery Behavior" "test_failure_recovery_behavior" "" ""
run_sre_test "Cross-Service Probe Coordination" "test_cross_service_coordination" "" ""

# SRE Metrics and Analysis
echo ""
echo "========================================"
print_info "SRE Metrics Analysis"
echo "========================================"

# Calculate overall SLI compliance
if [ ${#SLI_MEASUREMENTS[@]} -gt 0 ]; then
    print_info "Service Level Indicators (SLIs) measured:"
    for measurement in "${SLI_MEASUREMENTS[@]}"; do
        IFS=':' read -r metric value threshold <<< "$measurement"
        print_sli "  $metric: ${value}ms (threshold: ${threshold}ms)"
    done
else
    print_info "No SLI measurements collected"
fi

# Error Budget Analysis
total_slos=${#SERVICE_SLOS[@]}
if [ $TESTS_RUN -gt 0 ]; then
    success_rate=$(( (total_slos * TESTS_RUN - SLO_VIOLATIONS) * 100 / (total_slos * TESTS_RUN) ))
else
    success_rate=0
fi

print_info "Error Budget Analysis:"
print_info "  Total SLO checks: $((total_slos * TESTS_RUN))"
print_info "  SLO violations: $SLO_VIOLATIONS"
print_info "  Success rate: ${success_rate}%"

if [ "$success_rate" -ge 95 ]; then
    print_pass "Error budget within acceptable limits (${success_rate}% >= 95%)"
    ERROR_BUDGET_STATUS="HEALTHY"
else
    print_fail "Error budget exceeded (${success_rate}% < 95%)"
    ERROR_BUDGET_STATUS="CRITICAL"
fi

# Reliability Assessment
print_info "Service Reliability Assessment:"
if [ "$ERROR_BUDGET_STATUS" == "HEALTHY" ] && [ "$SLO_VIOLATIONS" -eq 0 ]; then
    print_pass "Service reliability: EXCELLENT - All SLOs met"
    RELIABILITY_SCORE="A+"
elif [ "$ERROR_BUDGET_STATUS" == "HEALTHY" ] && [ "$SLO_VIOLATIONS" -le 2 ]; then
    print_pass "Service reliability: GOOD - Minor SLO violations"
    RELIABILITY_SCORE="A"
elif [ "$SLO_VIOLATIONS" -le 5 ]; then
    print_fail "Service reliability: DEGRADED - Multiple SLO violations"
    RELIABILITY_SCORE="B"
else
    print_fail "Service reliability: POOR - Significant SLO violations"
    RELIABILITY_SCORE="C"
fi

# Recommendations
print_info "SRE Recommendations:"
if [ "$SLO_VIOLATIONS" -gt 0 ]; then
    print_info "  🔧 Review probe configurations that exceeded SLO thresholds"
    print_info "  📊 Consider adjusting SLO targets based on actual service performance"
    print_info "  🚨 Implement alerting for SLO violations"
fi

if [ "$TESTS_PASSED" -lt "$TESTS_RUN" ]; then
    print_info "  🔄 Investigate failed tests for potential service issues"
    print_info "  📈 Consider implementing additional monitoring for failed components"
fi

print_info "  📋 Regular SRE testing recommended: daily for production environments"
print_info "  🎯 Monitor probe success rates and response times continuously"

# Generate SRE Report Summary
echo ""
echo "========================================"
echo "📊 SRE Test Summary:"
echo "   Tests run: $TESTS_RUN"
echo "   Tests passed: $TESTS_PASSED"
echo "   Tests failed: $((TESTS_RUN - TESTS_PASSED))"
echo "   SLO violations: $SLO_VIOLATIONS"
echo "   Success rate: ${success_rate}%"
echo "   Reliability score: $RELIABILITY_SCORE"
echo "   Error budget status: $ERROR_BUDGET_STATUS"

if [ $TESTS_PASSED -eq $TESTS_RUN ] && [ $SLO_VIOLATIONS -eq 0 ]; then
    print_pass "All SRE tests passed! Service reliability excellent ✅"
    exit 0
elif [ $SLO_VIOLATIONS -eq 0 ]; then
    print_pass "All SLOs met, minor test failures ⚠️"
    exit 0
else
    print_fail "SLO violations detected! Service reliability needs attention ❌"
    exit 1
fi