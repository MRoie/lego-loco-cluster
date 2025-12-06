#!/usr/bin/env python3
"""
Resilience & Chaos Test Suite
Verifies system behavior under failure conditions (Phase 3)
"""

import subprocess
import json
import time
import sys
import re
from datetime import datetime

# Configuration
NAMESPACE = 'loco'
STATEFULSET = 'loco-loco-emulator'
BACKEND_URL = 'http://localhost:3001'
POLL_INTERVAL = 1
TIMEOUT = 60

# Colors
GREEN = '\033[92m'
RED = '\033[91m'
BLUE = '\033[94m'
YELLOW = '\033[93m'
RESET = '\033[0m'

def log(msg, color=RESET):
    print(f"{color}[{datetime.now().strftime('%H:%M:%S')}] {msg}{RESET}")

def run_command(cmd):
    try:
        result = subprocess.run(cmd, shell=True, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        # Don't fail immediately, let caller handle
        raise Exception(f"Command failed: {cmd}\n{e.stderr}")

def kubectl_exec(url):
    cmd = f"kubectl exec -n {NAMESPACE} deployment/loco-loco-backend -- wget -qO- {url}"
    result = run_command(cmd)
    return json.loads(result)

def get_emulator_pod():
    cmd = f"kubectl get pods -n {NAMESPACE} -l app=loco-loco-emulator -o jsonpath='{{.items[0].metadata.name}}'"
    return run_command(cmd)

def get_qemu_pid(pod):
    cmd = f"kubectl exec -n {NAMESPACE} {pod} -- ps aux | grep qemu-system | grep -v grep | awk '{{print $2}}'"
    return run_command(cmd).strip()

def wait_for_status(target_status, description):
    log(f"⏳ Waiting for status: {target_status} ({description})...", BLUE)
    start = time.time()
    
    while time.time() - start < TIMEOUT:
        try:
            data = kubectl_exec(f"{BACKEND_URL}/api/instances/live")
            instances = data['instances']
            if not instances:
                time.sleep(POLL_INTERVAL)
                continue
                
            inst = instances[0]
            
            # Check status match
            if inst['status'] == target_status:
                log(f"✅ Status is {target_status}", GREEN)
                return inst
            
            # Log current status occasionally
            if int(time.time()) % 5 == 0:
                log(f"   Current: {inst['status']} (Health: {inst.get('health', {}).get('ready')})", YELLOW)
                
        except Exception as e:
            pass
        time.sleep(POLL_INTERVAL)
    
    raise Exception(f"Timeout waiting for status {target_status}")

def run_test():
    try:
        log("🚀 Starting Resilience & Chaos Tests", GREEN)
        
        # 1. Setup
        log("\n🔧 Setup: Ensure 1 replica and healthy", YELLOW)
        run_command(f"kubectl scale statefulset {STATEFULSET} --replicas=1 -n {NAMESPACE}")
        pod = get_emulator_pod()
        log(f"Target Pod: {pod}")
        
        wait_for_status('ready', "Initial Healthy State")
        
        # 2. Chaos: Freeze VNC
        log("\n❄️  Chaos: Freezing QEMU process (Simulate Network/Service Hang)", YELLOW)
        pid = get_qemu_pid(pod)
        log(f"QEMU PID: {pid}")
        
        run_command(f"kubectl exec -n {NAMESPACE} {pod} -- kill -STOP {pid}")
        log("Process frozen. Waiting for probe timeout...", BLUE)
        
        # Expect 'degraded' because K8s says Running but Probe fails (timeout)
        inst = wait_for_status('degraded', "Service Frozen")
        
        # Verify details
        details = inst.get('health', {}).get('details', '')
        log(f"Failure Details: {details}")
        assert 'timeout' in details.lower() or 'failed' in details.lower(), "Error details should mention timeout/failure"
        
        # 3. Recovery
        log("\n🩹 Recovery: Unfreezing QEMU process", YELLOW)
        run_command(f"kubectl exec -n {NAMESPACE} {pod} -- kill -CONT {pid}")
        
        wait_for_status('ready', "Service Restored")
        
        log("\n✨ All Resilience Tests Passed!", GREEN)
        
    except Exception as e:
        log(f"\n❌ Test Failed: {e}", RED)
        # Try to cleanup
        try:
            if 'pid' in locals() and 'pod' in locals():
                run_command(f"kubectl exec -n {NAMESPACE} {pod} -- kill -CONT {pid}")
        except:
            pass
        sys.exit(1)

if __name__ == "__main__":
    run_test()
