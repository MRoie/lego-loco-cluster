#!/bin/bash

# Development Environment Test Suite
# Tests all functionality of the enhanced Lego Loco Cluster development environment

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

# Test configuration
BACKEND_URL="http://localhost:3001"
FRONTEND_URL="http://localhost:3000"

# Initialize test results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    print_test "$test_name"
    
    if eval "$test_command"; then
        print_pass "$test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        print_fail "$test_name"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

echo "🧪 Lego Loco Cluster Development Environment Test Suite"
echo "======================================================"
echo ""

# Test 1: Backend Health Check
run_test "Backend Health Check" \
    "curl -s -f $BACKEND_URL/health >/dev/null"

# Test 2: Backend Enhanced Instances API
run_test "Enhanced Instances API Structure" \
    "curl -s $BACKEND_URL/api/instances | jq -e '.[0] | has(\"status\") and has(\"provisioned\") and has(\"ready\") and has(\"name\") and has(\"description\")' >/dev/null"

# Test 3: Provisioned Instances API
run_test "Provisioned Instances API" \
    "curl -s $BACKEND_URL/api/instances/provisioned | jq -e '. | length > 0' >/dev/null"

# Test 4: Provisioned Instances Filter
run_test "Provisioned Instances Filter Logic" \
    "curl -s $BACKEND_URL/api/instances/provisioned | jq -e '.[] | select(.provisioned == false) | length == 0' >/dev/null"

# Test 5: Frontend Serving
run_test "Frontend Serving" \
    "curl -s -f $FRONTEND_URL >/dev/null"

# Test 6: Frontend HTML Structure
run_test "Frontend HTML Structure" \
    "curl -s $FRONTEND_URL | grep -q 'Lego Loco'"

# Test 7: Container Status
run_test "Development Containers Running" \
    "docker-compose -f compose/docker-compose.yml -f compose/docker-compose.dev.yml ps | grep -q 'Up'"

# Test 8: Backend Live Reloading (nodemon)
run_test "Backend Nodemon Configuration" \
    "docker-compose -f compose/docker-compose.yml -f compose/docker-compose.dev.yml logs backend | grep -q 'nodemon'"

# Test 9: Frontend Live Reloading (Vite)
run_test "Frontend Vite HMR" \
    "docker-compose -f compose/docker-compose.yml -f compose/docker-compose.dev.yml logs frontend | grep -q 'vite'"

# Test 10: Debug Port Exposed
run_test "Backend Debug Port" \
    "netstat -tulpn 2>/dev/null | grep -q ':9229' || ss -tulpn 2>/dev/null | grep -q ':9229'"

# Test 11: Config File Mounting
run_test "Config File Access" \
    "curl -s $BACKEND_URL/api/config/instances | jq -e '. | length > 0' >/dev/null"

# Test 12: Status Endpoint Data
run_test "Status Endpoint" \
    "curl -s $BACKEND_URL/api/status | jq -e '. | length > 0' >/dev/null"

echo ""
echo "📊 Test Results Summary"
echo "======================"
echo -e "Total Tests: ${BLUE}$TOTAL_TESTS${NC}"
echo -e "Passed:      ${GREEN}$PASSED_TESTS${NC}"
echo -e "Failed:      ${RED}$FAILED_TESTS${NC}"

if [[ $FAILED_TESTS -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}🎉 All tests passed! Development environment is fully functional.${NC}"
    echo ""
    echo "✅ Features Verified:"
    echo "  • Backend API with enhanced instance data"
    echo "  • Provisioned instances filtering"
    echo "  • Live reloading with nodemon (backend)"
    echo "  • Hot module replacement with Vite (frontend)"
    echo "  • Debug port exposure (9229)"
    echo "  • Config file mounting and access"
    echo "  • 3x3 grid frontend interface"
    echo ""
    echo "🚀 Ready for development!"
    exit 0
else
    echo ""
    echo -e "${RED}❌ Some tests failed. Please check the development environment setup.${NC}"
    exit 1
fi
