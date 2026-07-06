import subprocess
import json
import time
import sys
from datetime import datetime

# Configuration
API_URL = 'http://localhost:3001/api/instances/live'
NAMESPACE = 'loco'
STATEFULSET = 'loco-loco-emulator'
POLL_INTERVAL = 1
TIMEOUT = 60

# Colors
GREEN = '\033[92m'
RED = '\033[91m'
BLUE = '\033[94m'
RESET = '\033[0m'

def log(msg, color=RESET):
    print(f"{color}[{datetime.now().isoformat()}] {msg}{RESET}")

def run_command(cmd):
    try:
        result = subprocess.run(cmd, shell=True, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        raise Exception(f"Command failed: {cmd}\n{e.stderr}")

def fetch_api():
    # Use kubectl exec to reach localhost:3001 inside the cluster network
    cmd = f"kubectl exec -n {NAMESPACE} deployment/loco-loco-backend -- wget -qO- {API_URL}"
    output = run_command(cmd)
    return json.loads(output)

def wait_for_condition(description, condition_fn):
    log(f"Waiting for: {description}...", BLUE)
    start = time.time()
    
    while time.time() - start < TIMEOUT:
        try:
            if condition_fn():
                log(f"✅ Success: {description}", GREEN)
                return True
        except Exception as e:
            pass # Ignore transient errors
        time.sleep(POLL_INTERVAL)
    
    raise Exception(f"Timeout waiting for: {description}")

def run_test():
    try:
        log('🚀 Starting E2E Discovery Scaling Test (Python)', GREEN)

        # 1. Verify Initial State
        log('--- Step 1: Verify Initial State (1 replica) ---')
        run_command(f"kubectl scale statefulset {STATEFULSET} --replicas=1 -n {NAMESPACE}")
        
        def check_initial():
            data = fetch_api()
            return data['stats']['total'] == 1 and data['stats']['ready'] == 1
            
        wait_for_condition('1 instance ready', check_initial)

        # 2. Scale Up
        log('--- Step 2: Scale Up to 2 Replicas ---')
        run_command(f"kubectl scale statefulset {STATEFULSET} --replicas=2 -n {NAMESPACE}")
        
        # Wait for 2 instances (one might be booting)
        def check_scale_up():
            data = fetch_api()
            log(f"  Current: {data['stats']['total']} total, {data['stats']['ready']} ready, {data['stats']['notReady']} not ready")
            return data['stats']['total'] == 2
            
        wait_for_condition('2 instances detected (any status)', check_scale_up)

        log('✅ Scale up verified', GREEN)

        # 3. Scale Down
        log('--- Step 3: Scale Down to 1 Replica ---')
        run_command(f"kubectl scale statefulset {STATEFULSET} --replicas=1 -n {NAMESPACE}")
        
        def check_scale_down():
            data = fetch_api()
            log(f"  Current: {data['stats']['total']} total")
            return data['stats']['total'] == 1
            
        wait_for_condition('Return to 1 instance', check_scale_down)

        log('🎉 All tests passed!', GREEN)
    except Exception as e:
        log(f"❌ Test Failed: {str(e)}", RED)
        sys.exit(1)

if __name__ == "__main__":
    run_test()
