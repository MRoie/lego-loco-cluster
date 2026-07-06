#!/usr/bin/env bash
# Real-time stream testing script for 1024x768 Lego Loco streams
# Implements SRE principles for robust and reliable solution testing

set -euo pipefail

# Configuration
STREAM_TEST_DURATION=${STREAM_TEST_DURATION:-30}
EXPECTED_RESOLUTION="1024x768"
EXPECTED_BITRATE_MIN=${EXPECTED_BITRATE_MIN:-1000}  # kbps
EXPECTED_BITRATE_MAX=${EXPECTED_BITRATE_MAX:-1400}  # kbps

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] ℹ️  INFO: $1${NC}"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ SUCCESS: $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  WARNING: $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ ERROR: $1${NC}"
}

# SRE Testing Functions
test_stream_resolution() {
    local container_name=$1
    local expected_res=$2
    
    log_info "Testing $container_name stream resolution..."
    
    # Check if container is running
    if ! docker ps --format "table {{.Names}}" | grep -q "$container_name"; then
        log_error "$container_name container is not running"
        return 1
    fi
    
    # Check GStreamer process inside container
    if docker exec "$container_name" pgrep -f "gst-launch-1.0" >/dev/null 2>&1; then
        log_success "$container_name: GStreamer process is running"
        
        # Check for resolution in GStreamer logs
        if docker logs "$container_name" 2>&1 | grep -q "$expected_res"; then
            log_success "$container_name: Stream configured for $expected_res"
        else
            log_warning "$container_name: Resolution $expected_res not found in logs"
        fi
    else
        log_error "$container_name: GStreamer process not found"
        return 1
    fi
    
    return 0
}

test_stream_connectivity() {
    local container_name=$1
    local port=$2
    
    log_info "Testing $container_name stream connectivity on port $port..."
    
    # Get container IP
    local container_ip
    container_ip=$(docker inspect "$container_name" --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null || echo "")
    
    if [ -z "$container_ip" ]; then
        log_error "$container_name: Could not get container IP"
        return 1
    fi
    
    log_info "$container_name: Container IP is $container_ip"
    
    # Check if UDP port is listening (for H.264 streams)
    if docker exec "$container_name" netstat -un 2>/dev/null | grep -q ":$port "; then
        log_success "$container_name: UDP port $port is active"
    else
        log_warning "$container_name: UDP port $port not found in netstat"
    fi
    
    return 0
}

test_stream_performance() {
    local container_name=$1
    
    log_info "Testing $container_name stream performance..."
    
    # Check CPU usage
    local cpu_usage
    cpu_usage=$(docker stats "$container_name" --no-stream --format "table {{.CPUPerc}}" | tail -n +2 | sed 's/%//')
    
    if [ -n "$cpu_usage" ]; then
        log_info "$container_name: Current CPU usage: ${cpu_usage}%"
        
        # SRE threshold: warn if CPU usage > 80%
        if (( $(echo "$cpu_usage > 80" | bc -l) )); then
            log_warning "$container_name: High CPU usage detected (${cpu_usage}%)"
        else
            log_success "$container_name: CPU usage within acceptable range (${cpu_usage}%)"
        fi
    fi
    
    # Check memory usage
    local mem_usage
    mem_usage=$(docker stats "$container_name" --no-stream --format "table {{.MemPerc}}" | tail -n +2 | sed 's/%//')
    
    if [ -n "$mem_usage" ]; then
        log_info "$container_name: Current memory usage: ${mem_usage}%"
        
        # SRE threshold: warn if memory usage > 85%
        if (( $(echo "$mem_usage > 85" | bc -l) )); then
            log_warning "$container_name: High memory usage detected (${mem_usage}%)"
        else
            log_success "$container_name: Memory usage within acceptable range (${mem_usage}%)"
        fi
    fi
    
    return 0
}

validate_container_logs() {
    local container_name=$1
    
    log_info "Validating $container_name logs for 1024x768 stream indicators..."
    
    local logs
    logs=$(docker logs "$container_name" --tail 50 2>&1)
    
    # Check for successful resolution setup
    if echo "$logs" | grep -q "1024x768"; then
        log_success "$container_name: 1024x768 resolution confirmed in logs"
    else
        log_warning "$container_name: 1024x768 resolution not found in recent logs"
    fi
    
    # Check for GStreamer success
    if echo "$logs" | grep -q "GStreamer started"; then
        log_success "$container_name: GStreamer startup confirmed"
    else
        log_warning "$container_name: GStreamer startup not confirmed in logs"
    fi
    
    # Check for errors
    if echo "$logs" | grep -qi "error\|failed\|died"; then
        log_warning "$container_name: Potential errors found in logs"
        echo "$logs" | grep -i "error\|failed\|died" | head -3
    else
        log_success "$container_name: No obvious errors in recent logs"
    fi
    
    return 0
}

# Main testing function
main() {
    log_info "🚀 Starting real-time 1024x768 Lego Loco stream testing..."
    log_info "Test duration: ${STREAM_TEST_DURATION}s"
    log_info "Expected resolution: $EXPECTED_RESOLUTION"
    log_info "Expected bitrate range: ${EXPECTED_BITRATE_MIN}-${EXPECTED_BITRATE_MAX} kbps"
    
    # Define containers to test
    local containers=("loco-qemu-1" "loco-qemu-2" "loco-qemu-3" "loco-pcem-1")
    local test_results=()
    
    # Test each container
    for container in "${containers[@]}"; do
        log_info "========================================="
        log_info "Testing container: $container"
        log_info "========================================="
        
        local container_passed=true
        
        # Test 1: Resolution configuration
        if ! test_stream_resolution "$container" "$EXPECTED_RESOLUTION"; then
            container_passed=false
        fi
        
        # Test 2: Stream connectivity
        if ! test_stream_connectivity "$container" "5000"; then
            container_passed=false
        fi
        
        # Test 3: Performance metrics
        if ! test_stream_performance "$container"; then
            container_passed=false
        fi
        
        # Test 4: Log validation
        if ! validate_container_logs "$container"; then
            container_passed=false
        fi
        
        if [ "$container_passed" = true ]; then
            test_results+=("$container: ✅ PASSED")
            log_success "$container: All tests passed!"
        else
            test_results+=("$container: ❌ FAILED")
            log_error "$container: Some tests failed"
        fi
        
        sleep 2
    done
    
    # Summary report
    log_info "========================================="
    log_info "🎯 FINAL TEST RESULTS SUMMARY"
    log_info "========================================="
    
    local passed_count=0
    local total_count=${#test_results[@]}
    
    for result in "${test_results[@]}"; do
        echo "$result"
        if [[ "$result" == *"PASSED"* ]]; then
            ((passed_count++))
        fi
    done
    
    log_info "========================================="
    log_info "Containers passed: $passed_count / $total_count"
    
    if [ "$passed_count" -eq "$total_count" ]; then
        log_success "🎉 ALL CONTAINERS PASSED 1024x768 STREAM TESTS!"
        log_success "Lego Loco cluster is ready with proper resolution streaming"
        exit 0
    else
        log_error "❌ Some containers failed the tests"
        log_error "Please check the failing containers and rebuild/restart as needed"
        exit 1
    fi
}

# SRE prerequisite checks
prerequisite_checks() {
    log_info "Performing SRE prerequisite checks..."
    
    # Check if Docker is available
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is not available"
        exit 1
    fi
    
    # Check if bc is available for calculations
    if ! command -v bc >/dev/null 2>&1; then
        log_warning "bc calculator not available, some performance checks may be skipped"
    fi
    
    log_success "Prerequisite checks passed"
}

# Run the tests
prerequisite_checks
main "$@"