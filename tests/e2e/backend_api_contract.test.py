#!/usr/bin/env python3
"""
Backend API Contract Tests for Service Discovery (Phase 1 + 2)
Tests all backend endpoints to ensure they return expected structure and data
"""

import subprocess
import json
import sys
from datetime import datetime

# Configuration
NAMESPACE = 'loco'
BACKEND_URL = 'http://localhost:3001'

GREEN = '\033[92m'
RED = '\033[91m'
BLUE = '\033[94m'
YELLOW = '\033[93m'
RESET = '\033[0m'

class TestResults:
    def __init__(self):
        self.passed = 0
        self.failed = 0
        self.tests = []
    
    def add_pass(self, name, details=""):
        self.passed += 1
        self.tests.append({"name": name, "status": "PASS", "details": details})
        print(f"{GREEN}✓ {name}{RESET}")
        if details:
            print(f"  {details}")
    
    def add_fail(self, name, error):
        self.failed += 1
        self.tests.append({"name": name, "status": "FAIL", "error": str(error)})
        print(f"{RED}✗ {name}{RESET}")
        print(f"  Error: {error}")
    
    def summary(self):
        total = self.passed + self.failed
        print(f"\n{'='*60}")
        print(f"Test Summary: {self.passed}/{total} passed")
        if self.failed > 0:
            print(f"{RED}FAILED: {self.failed} tests{RESET}")
            return False
        else:
            print(f"{GREEN}ALL TESTS PASSED{RESET}")
            return True

def log(msg, color=RESET):
    print(f"{color}[{datetime.now().strftime('%H:%M:%S')}] {msg}{RESET}")

def kubectl_exec(url):
    """Execute wget inside backend pod to hit localhost endpoints"""
    cmd = f"kubectl exec -n {NAMESPACE} deployment/loco-loco-backend -- wget -qO- {url}"
    result = subprocess.run(cmd, shell=True, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    return json.loads(result.stdout)

def test_api_instances_live(results):
    """Test GET /api/instances/live - Core Phase 2 endpoint"""
    try:
        data = kubectl_exec(f"{BACKEND_URL}/api/instances/live")
        
        # Validate structure
        assert 'mode' in data, "Missing 'mode' field"
        assert 'stats' in data, "Missing 'stats' field"
        assert 'instances' in data, "Missing 'instances' field"
        assert 'lastUpdate' in data, "Missing 'lastUpdate' field"
        
        # Validate stats structure
        stats = data['stats']
        assert 'total' in stats, "Missing stats.total"
        assert 'ready' in stats, "Missing stats.ready"
        assert 'notReady' in stats, "Missing stats.notReady"
        
        # Validate mode is one of expected values
        assert data['mode'] in ['kubernetes-endpoints', 'kubernetes-pods', 'static'], f"Invalid mode: {data['mode']}"
        
        # Validate instances array
        assert isinstance(data['instances'], list), "instances should be an array"
        
        # If we have instances, validate structure
        if len(data['instances']) > 0:
            inst = data['instances'][0]
            required_fields = ['id', 'status', 'provisioned', 'addresses', 'ports', 'health']
            for field in required_fields:
                assert field in inst, f"Missing field '{field}' in instance"
        
        details = f"Mode: {data['mode']}, Stats: {stats}"
        results.add_pass("GET /api/instances/live", details)
    except Exception as e:
        results.add_fail("GET /api/instances/live", e)

def test_api_instances(results):
    """Test GET /api/instances - Legacy endpoint"""
    try:
        data = kubectl_exec(f"{BACKEND_URL}/api/instances")
        assert isinstance(data, list), "Should return array of instances"
        results.add_pass("GET /api/instances")
    except Exception as e:
        results.add_fail("GET /api/instances", e)

def test_api_status(results):
    """Test GET /api/status - Backend health"""
    try:
        data = kubectl_exec(f"{BACKEND_URL}/api/status")
        assert 'status' in data or 'uptime' in data or 'version' in data, "Invalid status response"
        results.add_pass("GET /api/status")
    except Exception as e:
        results.add_fail("GET /api/status", e)

def test_discovery_mode_detection(results):
    """Verify discovery mode is correctly detected as kubernetes-endpoints"""
    try:
        data = kubectl_exec(f"{BACKEND_URL}/api/instances/live")
        mode = data['mode']
        
        # In our minikube setup, should be using endpoints
        if mode == 'kubernetes-endpoints':
            results.add_pass("Discovery Mode Detection", f"Correctly using '{mode}'")
        else:
            results.add_fail("Discovery Mode Detection", f"Expected 'kubernetes-endpoints', got '{mode}'")
    except Exception as e:
        results.add_fail("Discovery Mode Detection", e)

def test_instance_metadata_completeness(results):
    """Verify instance objects have all required metadata from Endpoints discovery"""
    try:
        data = kubectl_exec(f"{BACKEND_URL}/api/instances/live")
        instances = data['instances']
        
        if len(instances) == 0:
            results.add_fail("Instance Metadata", "No instances found to test")
            return
        
        inst = instances[0]
        
        # Phase 1 required fields
        required_phase1 = ['podName', 'addresses', 'kubernetes']
        for field in required_phase1:
            assert field in inst, f"Missing Phase 1 field: {field}"
        
        # Addresses should have podIP, hostname, dnsName
        addr = inst['addresses']
        assert 'podIP' in addr, "Missing addresses.podIP"
        assert 'hostname' in addr, "Missing addresses.hostname"
        assert 'dnsName' in addr, "Missing addresses.dnsName"
        
        # Kubernetes metadata
        k8s = inst['kubernetes']
        assert 'namespace' in k8s, "Missing kubernetes.namespace"
        assert 'targetRef' in k8s, "Missing kubernetes.targetRef"
        
        results.add_pass("Instance Metadata Completeness", f"Pod: {inst['podName']}")
    except Exception as e:
        results.add_fail("Instance Metadata Completeness", e)

def test_stats_accuracy(results):
    """Verify stats.total matches actual instance count"""
    try:
        data = kubectl_exec(f"{BACKEND_URL}/api/instances/live")
        stats = data['stats']
        instances = data['instances']
        
        assert stats['total'] == len(instances), f"stats.total ({stats['total']}) != actual count ({len(instances)})"
        assert stats['ready'] + stats['notReady'] == stats['total'], "ready + notReady should equal total"
        
        results.add_pass("Stats Accuracy", f"{stats}")
    except Exception as e:
        results.add_fail("Stats Accuracy", e)

def run_all_tests():
    log("🧪 Starting Backend API Contract Tests (Phase 1 + 2)", BLUE)
    log(f"Target: {BACKEND_URL}", BLUE)
    
    results = TestResults()
    
    # Core API tests
    log("\n📋 Testing Core API Endpoints...", YELLOW)
    test_api_instances_live(results)
    test_api_instances(results)
    test_api_status(results)
    
    # Discovery validation tests
    log("\n🔍 Testing Discovery Logic...", YELLOW)
    test_discovery_mode_detection(results)
    test_instance_metadata_completeness(results)
    test_stats_accuracy(results)
    
    # Print summary
    success = results.summary()
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    run_all_tests()
