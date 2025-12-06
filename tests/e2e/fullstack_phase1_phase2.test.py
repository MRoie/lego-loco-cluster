#!/usr/bin/env python3
"""
Full Stack E2E Test for Service Discovery (Phase 1 + 2)
Combines backend API validation with frontend behavior verification
Tests the complete scaling scenario: 1 -> 2 -> 1 instances
"""

import subprocess
import json
import time
import sys
from datetime import datetime

# Configuration
NAMESPACE = 'loco'
STATEFULSET = 'loco-loco-emulator'
BACKEND_URL = 'http://localhost:3001'
POLL_INTERVAL = 1
TIMEOUT = 90

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
        print(f"\n{'='*80}")
        print(f"Full Stack E2E Test Summary: {self.passed}/{total} passed")
        if self.failed > 0:
            print(f"{RED}FAILED: {self.failed} tests{RESET}")
            return False
        else:
            print(f"{GREEN}ALL TESTS PASSED ✨{RESET}")
            return True

def log(msg, color=RESET):
    print(f"{color}[{datetime.now().strftime('%H:%M:%S')}] {msg}{RESET}")

def run_command(cmd):
    result = subprocess.run(cmd, shell=True, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    return result.stdout.strip()

def kubectl_exec(url):
    cmd = f"kubectl exec -n {NAMESPACE} deployment/loco-loco-backend -- wget -qO- {url}"
    result = run_command(cmd)
    return json.loads(result)

def wait_for_condition(description, condition_fn):
    log(f"⏳ Waiting for: {description}...", BLUE)
    start = time.time()
    
    while time.time() - start < TIMEOUT:
        try:
            if condition_fn():
                log(f"✅ {description}", GREEN)
                return True
        except Exception:
            pass
        time.sleep(POLL_INTERVAL)
    
    raise Exception(f"Timeout after {TIMEOUT}s waiting for: {description}")

def test_phase1_backend_discovery(results):
    """Phase 1: Verify Endpoints Discovery is working"""
    try:
        data = kubectl_exec(f"{BACKEND_URL}/api/instances/live")
        
        # Should be using kubernetes-endpoints
        assert data['mode'] == 'kubernetes-endpoints', f"Expected kubernetes-endpoints, got {data['mode']}"
        
        # Should have serviceName
        assert 'serviceName' in data, "Missing serviceName"
        assert data['serviceName'] == 'loco-loco-emulator', f"Wrong service name: {data['serviceName']}"
        
        results.add_pass("Phase 1: Endpoints Discovery Active", f"Service: {data['serviceName']}")
    except Exception as e:
        results.add_fail("Phase 1: Endpoints Discovery Active", e)

def test_phase1_instance_kubernetes_metadata(results):
    """Phase 1: Verify Kubernetes metadata is populated"""
    try:
        data = kubectl_exec(f"{BACKEND_URL}/api/instances/live")
        instances = data['instances']
        
        assert len(instances) > 0, "No instances found"
        
        inst = instances[0]
        
        # Verify Phase 1 requirements
        assert 'kubernetes' in inst, "Missing kubernetes metadata"
        k8s = inst['kubernetes']
        assert k8s['namespace'] == NAMESPACE, f"Wrong namespace: {k8s['namespace']}"
        assert 'targetRef' in k8s, "Missing targetRef"
        assert k8s['targetRef']['kind'] == 'Pod', f"Wrong ref kind: {k8s['targetRef']['kind']}"
        
        # Verify addresses from Endpoints
        assert 'addresses' in inst, "Missing addresses"
        addr = inst['addresses']
        assert 'podIP' in addr, "Missing podIP"
        assert 'dnsName' in addr, "Missing dnsName"
        
        results.add_pass("Phase 1: Kubernetes Metadata", f"Pod: {inst['podName']}, IP: {addr['podIP']}")
    except Exception as e:
        results.add_fail("Phase 1: Kubernetes Metadata", e)

def test_phase2_live_endpoint_realtime(results):
    """Phase 2: Verify /api/instances/live returns real-time data"""
    try:
        # Get initial state
        data1 = kubectl_exec(f"{BACKEND_URL}/api/instances/live")
        time1 = data1.get('lastUpdate')
        
        # Wait a bit
        time.sleep(2)
        
        # Get again - lastUpdate should be recent (within last 35s due to 30s poll)
        data2 = kubectl_exec(f"{BACKEND_URL}/api/instances/live")
        time2 = data2.get('lastUpdate')
        
        # Verify it's updating
        assert time2 is not None, "lastUpdate is missing"
        
        # Parse timestamp
        from datetime import datetime
        update_time = datetime.fromisoformat(time2.replace('Z', '+00:00'))
        now = datetime.now(update_time.tzinfo)
        age_seconds = (now - update_time).total_seconds()
        
        # Should be less than 40 seconds old (30s poll + margin)
        assert age_seconds < 40, f"Data too stale: {age_seconds}s old"
        
        results.add_pass("Phase 2: Real-time Updates", f"Last update: {age_seconds:.1f}s ago")
    except Exception as e:
        results.add_fail("Phase 2: Real-time Updates", e)

def test_phase2_stats_reporting(results):
    """Phase 2: Verify stats are accurately reported"""
    try:
        data = kubectl_exec(f"{BACKEND_URL}/api/instances/live")
        stats = data['stats']
        instances = data['instances']
        
        # Count actual ready/notReady
        actual_ready = sum(1 for i in instances if i.get('health', {}).get('ready', False))
        actual_not_ready = len(instances) - actual_ready
        
        # Verify stats match
        assert stats['total'] == len(instances), "total count mismatch"
        assert stats['ready'] == actual_ready, f"ready count mismatch: {stats['ready']} vs {actual_ready}"
        assert stats['notReady'] == actual_not_ready, f"notReady count mismatch"
        
        results.add_pass("Phase 2: Stats Reporting", f"Total:{stats['total']}, Ready:{stats['ready']}")
    except Exception as e:
        results.add_fail("Phase 2: Stats Reporting", e)

def test_fullstack_scaling_up(results):
    """Full Stack: Scale up and verify backend detects new instance"""
    try:
        log("📈 Scaling up to 2 replicas...", YELLOW)
        run_command(f"kubectl scale statefulset {STATEFULSET} --replicas=2 -n {NAMESPACE}")
        
        def check_2_instances():
            data = kubectl_exec(f"{BACKEND_URL}/api/instances/live")
            count = data['stats']['total']
            log(f"  Current: {count} instances", BLUE)
            return count == 2
        
        wait_for_condition("Backend detects 2 instances", check_2_instances)
        
        # Verify both instances are present
        data = kubectl_exec(f"{BACKEND_URL}/api/instances/live")
        assert len(data['instances']) == 2, "Should have 2 instance objects"
        
        # At least one should be ready
        ready_count = data['stats']['ready']
        assert ready_count >= 1, "At least 1 instance should be ready"
        
        results.add_pass("Full Stack: Scale Up Detection", f"Detected 2 instances ({ready_count} ready)")
    except Exception as e:
        results.add_fail("Full Stack: Scale Up Detection", e)

def test_fullstack_scaling_down(results):
    """Full Stack: Scale down and verify backend updates"""
    try:
        log("📉 Scaling down to 1 replica...", YELLOW)
        run_command(f"kubectl scale statefulset {STATEFULSET} --replicas=1 -n {NAMESPACE}")
        
        def check_1_instance():
            data = kubectl_exec(f"{BACKEND_URL}/api/instances/live")
            count = data['stats']['total']
            log(f"  Current: {count} instances", BLUE)
            return count == 1
        
        wait_for_condition("Backend detects 1 instance", check_1_instance)
        
        # Verify only one instance
        data = kubectl_exec(f"{BACKEND_URL}/api/instances/live")
        assert len(data['instances']) == 1, "Should have 1 instance object"
        assert data['stats']['ready'] == 1, "Instance should be ready"
        
        results.add_pass("Full Stack: Scale Down Detection", "Successfully returned to 1 instance")
    except Exception as e:
        results.add_fail("Full Stack: Scale Down Detection", e)

def run_all_tests():
    log("🚀 Starting Full Stack E2E Tests (Phase 1 + 2)", GREEN)
    log(f"Target: {BACKEND_URL}", GREEN)
    log(f"Cluster: {NAMESPACE}", GREEN)
    
    results = TestResults()
    
    # Ensure starting state (1 instance)
    try:
        log("\n🔧 Setting up initial state (1 replica)...", YELLOW)
        run_command(f"kubectl scale statefulset {STATEFULSET} --replicas=1 -n {NAMESPACE}")
        time.sleep(5)
        wait_for_condition("Initial 1 instance ready", lambda: kubectl_exec(f"{BACKEND_URL}/api/instances/live")['stats']['total'] == 1)
    except Exception as e:
        log(f"Failed to setup initial state: {e}", RED)
        sys.exit(1)
    
    # Phase 1 Tests
    log("\n📦 Phase 1: Endpoints Discovery Tests", YELLOW)
    test_phase1_backend_discovery(results)
    test_phase1_instance_kubernetes_metadata(results)
    
    # Phase 2 Tests
    log("\n📡 Phase 2: Live Discovery API Tests", YELLOW)
    test_phase2_live_endpoint_realtime(results)
    test_phase2_stats_reporting(results)
    
    # Full Stack Tests
    log("\n🔄 Full Stack: Scaling Scenario Tests", YELLOW)
    test_fullstack_scaling_up(results)
    test_fullstack_scaling_down(results)
    
    # Summary
    success = results.summary()
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    run_all_tests()
