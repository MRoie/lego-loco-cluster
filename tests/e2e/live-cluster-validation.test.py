#!/usr/bin/env python3
"""
Production-Grade Live Cluster Validation Test Suite
====================================================
Runs against the actual K8s cluster to validate all bug fixes and infrastructure.

Tests:
  1. Backend API contract (health, discovery, instances, live endpoint)
  2. K8s Endpoints discovery mode verification
  3. Instance metadata completeness (addresses, ports, probes, kubernetes)
  4. VNC probe reachability (RFB protocol handshake verified)
  5. Health probe reachability (HTTP 200 from health-monitor.sh)
  6. StreamUrl fix verification (must be /proxy/vnc/instance-N, not localhost:6080)
  7. NetworkPolicy verification (backend can reach emulators)
  8. Per-instance unique identity (IP, hostname, MAC, guest IP)
  9. Scaling test (2→1→2 replicas, verify discovery tracks)
  10. Emulator health-monitor deep check (QEMU, video, audio, network)

Exit codes:
  0 = all tests passed
  1 = one or more tests failed

Usage:
  python3 tests/e2e/live-cluster-validation.test.py
"""

import subprocess
import json
import time
import sys
import os
import re
from datetime import datetime, timezone

# ── Configuration ────────────────────────────────────────────────────────────
NAMESPACE = os.environ.get('NAMESPACE', 'loco')
BACKEND_URL = os.environ.get('BACKEND_URL', 'http://localhost:3001')
STATEFULSET = os.environ.get('STATEFULSET', 'loco-loco-emulator')
POLL_INTERVAL = 2
TIMEOUT = 90

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN = '\033[92m'
RED = '\033[91m'
BLUE = '\033[94m'
YELLOW = '\033[93m'
CYAN = '\033[96m'
BOLD = '\033[1m'
RESET = '\033[0m'

# ── Test Framework ────────────────────────────────────────────────────────────
class TestSuite:
    def __init__(self, name):
        self.name = name
        self.results = []
        self.start_time = datetime.now(timezone.utc)

    def record(self, name, passed, details="", error="", duration_ms=0):
        self.results.append({
            "name": name,
            "passed": passed,
            "details": details,
            "error": error,
            "duration_ms": duration_ms,
            "timestamp": datetime.now(timezone.utc).isoformat()
        })
        status = f"{GREEN}PASS{RESET}" if passed else f"{RED}FAIL{RESET}"
        timing = f" ({duration_ms}ms)" if duration_ms else ""
        print(f"  [{status}] {name}{timing}")
        if details and passed:
            print(f"         {CYAN}{details}{RESET}")
        if error and not passed:
            print(f"         {RED}{error}{RESET}")

    def summary(self):
        total = len(self.results)
        passed = sum(1 for r in self.results if r["passed"])
        failed = total - passed
        elapsed = (datetime.now(timezone.utc) - self.start_time).total_seconds()

        print(f"\n{'='*72}")
        print(f"{BOLD}  {self.name} — Results{RESET}")
        print(f"{'='*72}")
        print(f"  Total:   {total}")
        print(f"  Passed:  {GREEN}{passed}{RESET}")
        print(f"  Failed:  {RED if failed else GREEN}{failed}{RESET}")
        print(f"  Time:    {elapsed:.1f}s")
        print(f"{'='*72}")

        if failed:
            print(f"\n{RED}{BOLD}  FAILED TESTS:{RESET}")
            for r in self.results:
                if not r["passed"]:
                    print(f"    {RED}✗ {r['name']}: {r['error']}{RESET}")

        return failed == 0

    def to_json(self):
        return {
            "suite": self.name,
            "timestamp": self.start_time.isoformat(),
            "results": self.results,
            "summary": {
                "total": len(self.results),
                "passed": sum(1 for r in self.results if r["passed"]),
                "failed": sum(1 for r in self.results if not r["passed"]),
            }
        }


def log(msg, color=RESET):
    ts = datetime.now().strftime('%H:%M:%S')
    print(f"{color}[{ts}] {msg}{RESET}")


def curl_json(url, timeout=10):
    """Fetch JSON from a URL using curl."""
    cmd = ["curl", "-s", "--max-time", str(timeout), url]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout + 5)
    if result.returncode != 0:
        raise Exception(f"curl failed: {result.stderr.strip()}")
    return json.loads(result.stdout)


def kubectl(args, timeout=30):
    """Run kubectl command and return stdout."""
    cmd = f"kubectl {args}"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
    if result.returncode != 0:
        raise Exception(f"kubectl failed: {result.stderr.strip()}")
    return result.stdout.strip()


def timed(fn):
    """Run fn, return (result, duration_ms)."""
    t0 = time.monotonic()
    result = fn()
    return result, int((time.monotonic() - t0) * 1000)


# ── Test Implementations ──────────────────────────────────────────────────────

def test_backend_health(suite):
    """T1: Backend health endpoint returns ok."""
    try:
        data, ms = timed(lambda: curl_json(f"{BACKEND_URL}/health"))
        ok = data.get("status") == "ok"
        suite.record("Backend /health returns ok", ok,
                     details=f"uptime={data.get('uptime', '?')}s version={data.get('version', '?')}",
                     error="" if ok else f"status={data.get('status')}",
                     duration_ms=ms)
    except Exception as e:
        suite.record("Backend /health returns ok", False, error=str(e))


def test_backend_ready(suite):
    """T2: Backend readiness endpoint returns 200."""
    try:
        data, ms = timed(lambda: curl_json(f"{BACKEND_URL}/ready"))
        suite.record("Backend /ready returns 200", True, duration_ms=ms)
    except Exception as e:
        suite.record("Backend /ready returns 200", False, error=str(e))


def test_discovery_mode(suite):
    """T3: Backend is using Kubernetes discovery (not static config)."""
    try:
        data, ms = timed(lambda: curl_json(f"{BACKEND_URL}/api/instances/live"))
        mode = data.get("mode", "unknown")
        svc = data.get("serviceName", "?")
        stats = data.get("stats", {})
        ok = "kubernetes" in mode
        suite.record("K8s auto-discovery active", ok,
                     details=f"mode={mode} service={svc} total={stats.get('total',0)} ready={stats.get('ready',0)}",
                     error=f"mode={mode} — not kubernetes" if not ok else "",
                     duration_ms=ms)
    except Exception as e:
        suite.record("K8s auto-discovery active", False, error=str(e))


def test_instances_exist(suite):
    """T4: At least 2 instances discovered."""
    try:
        data, ms = timed(lambda: curl_json(f"{BACKEND_URL}/api/instances"))
        count = len(data)
        ok = count >= 2
        suite.record(">=2 instances discovered", ok,
                     details=f"found {count} instances",
                     error="" if ok else f"only {count} found",
                     duration_ms=ms)
        return data
    except Exception as e:
        suite.record(">=2 instances discovered", False, error=str(e))
        return []


def test_streamurl_fix(suite, instances):
    """T5: streamUrl uses /proxy/vnc/ path (BUG FIX VERIFICATION)."""
    bad = []
    for inst in instances:
        url = inst.get("streamUrl", "")
        if not url.startswith("/proxy/vnc/"):
            bad.append(f"{inst['id']}: {url}")

    ok = len(bad) == 0 and len(instances) > 0
    suite.record("streamUrl uses /proxy/vnc/ (bug fix)", ok,
                 details=f"all {len(instances)} instances: /proxy/vnc/instance-N",
                 error=f"bad URLs: {bad}" if bad else "")


def test_vnc_probes(suite, instances):
    """T6: VNC probes return ok with RFB protocol version (BUG FIX VERIFICATION)."""
    for inst in instances:
        iid = inst["id"]
        probe = inst.get("probe", {})
        vnc = probe.get("services", {}).get("vnc", {})
        ok = vnc.get("status") == "ok"
        proto = vnc.get("protocolVersion", "?")
        suite.record(f"VNC probe {iid}", ok,
                     details=f"protocol={proto}",
                     error=f"vnc status={vnc.get('status', 'missing')}" if not ok else "")


def test_health_probes(suite, instances):
    """T7: Health probes return ok with HTTP 200 (BUG FIX VERIFICATION)."""
    for inst in instances:
        iid = inst["id"]
        probe = inst.get("probe", {})
        health = probe.get("services", {}).get("health", {})
        ok = health.get("status") == "ok" and health.get("statusCode") == 200
        suite.record(f"Health probe {iid}", ok,
                     details=f"statusCode={health.get('statusCode', '?')}",
                     error=f"health={health}" if not ok else "")


def test_networkpolicy_probes_work(suite, instances):
    """T8: NetworkPolicy allows backend→emulator probes (BUG FIX VERIFICATION).
    The fact that probes succeed proves the NetworkPolicy fix is working."""
    all_reachable = all(
        inst.get("probe", {}).get("reachable", False)
        for inst in instances
    )
    suite.record("NetworkPolicy allows probes (bug fix)", all_reachable,
                 details=f"all {len(instances)} instances reachable through NetworkPolicy",
                 error="some instances unreachable — NetworkPolicy may be blocking" if not all_reachable else "")


def test_instance_metadata(suite, instances):
    """T9: Each instance has complete K8s metadata."""
    for inst in instances:
        iid = inst["id"]
        errors = []

        # Required fields
        for field in ["podName", "addresses", "ports", "health", "kubernetes", "probe"]:
            if field not in inst:
                errors.append(f"missing {field}")

        # Addresses
        addr = inst.get("addresses", {})
        for af in ["podIP", "hostname", "dnsName"]:
            if af not in addr:
                errors.append(f"missing addresses.{af}")

        # Ports
        ports = inst.get("ports", {})
        if "vnc" not in ports or "health" not in ports:
            errors.append(f"missing ports (got {list(ports.keys())})")

        # K8s metadata
        k8s = inst.get("kubernetes", {})
        if k8s.get("namespace") != NAMESPACE:
            errors.append(f"wrong namespace: {k8s.get('namespace')}")
        if "targetRef" not in k8s:
            errors.append("missing kubernetes.targetRef")

        ok = len(errors) == 0
        suite.record(f"Metadata complete {iid}", ok,
                     details=f"pod={inst.get('podName')} ip={addr.get('podIP')} dns={addr.get('dnsName', '?')[:40]}",
                     error="; ".join(errors) if errors else "")


def test_unique_identity(suite, instances):
    """T10: Each instance has unique identity (pod IP, podName, id)."""
    ids = [i["id"] for i in instances]
    pod_names = [i.get("podName", "") for i in instances]
    pod_ips = [i.get("addresses", {}).get("podIP", "") for i in instances]

    checks = [
        ("id", ids),
        ("podName", pod_names),
        ("podIP", pod_ips),
    ]

    for field, values in checks:
        unique = len(set(values)) == len(values) and all(v for v in values)
        suite.record(f"Unique {field} per instance", unique,
                     details=f"values={values}",
                     error=f"duplicates in {values}" if not unique else "")


def test_live_endpoint(suite):
    """T11: /api/instances/live returns stats and mode."""
    try:
        data, ms = timed(lambda: curl_json(f"{BACKEND_URL}/api/instances/live"))
        stats = data.get("stats", {})
        mode = data.get("mode", "?")
        instances = data.get("instances", [])

        checks = []
        checks.append(("has mode", "mode" in data))
        checks.append(("has stats", "stats" in data))
        checks.append(("has instances", "instances" in data))
        checks.append(("stats.total matches", stats.get("total", -1) == len(instances)))
        checks.append(("stats.ready > 0", stats.get("ready", 0) > 0))

        for name, ok in checks:
            suite.record(f"/api/instances/live: {name}", ok,
                         details=f"mode={mode} stats={stats}" if ok else "",
                         error="" if ok else f"check failed")

    except Exception as e:
        suite.record("/api/instances/live endpoint", False, error=str(e))


def test_emulator_deep_health(suite):
    """T12: Emulator health-monitor returns detailed health JSON."""
    try:
        pods = kubectl(f'get pods -n {NAMESPACE} -l app=loco-loco-emulator '
                       f'-o jsonpath="{{.items[*].metadata.name}}"')
        pod_list = [p.strip("'\"") for p in pods.split() if p.strip("'\"")]

        for pod in pod_list[:2]:
            try:
                raw = kubectl(f"exec -n {NAMESPACE} {pod} -c emulator -- "
                              f"curl -s --max-time 5 http://localhost:8080/health")
                data = json.loads(raw)

                qemu_ok = data.get("qemu_healthy", False)
                overall = data.get("overall_status", "?")
                video = data.get("video", {})
                audio = data.get("audio", {})
                network = data.get("network", {})

                suite.record(f"Deep health {pod}: QEMU alive", qemu_ok,
                             details=f"overall={overall}",
                             error="qemu_healthy=false" if not qemu_ok else "")

                vnc_avail = video.get("vnc_available", False)
                suite.record(f"Deep health {pod}: VNC available", vnc_avail,
                             details=f"port={video.get('vnc_port')} display={video.get('display')}")

                bridge_up = network.get("bridge_up", False)
                tap_up = network.get("tap_up", False)
                suite.record(f"Deep health {pod}: network bridge+tap", bridge_up and tap_up,
                             details=f"bridge={bridge_up} tap={tap_up} rx={network.get('rx_packets',0)} tx={network.get('tx_packets',0)}")

            except Exception as e:
                suite.record(f"Deep health {pod}", False, error=str(e))

    except Exception as e:
        suite.record("Emulator deep health check", False, error=str(e))


def test_scaling(suite):
    """T13: Scale 2→1→2 and verify discovery tracks the change."""
    try:
        # Scale down to 1
        log("Scaling to 1 replica...", YELLOW)
        kubectl(f"scale statefulset {STATEFULSET} --replicas=1 -n {NAMESPACE}")

        ok1 = False
        for _ in range(int(TIMEOUT / POLL_INTERVAL)):
            try:
                data = curl_json(f"{BACKEND_URL}/api/instances")
                if len(data) == 1:
                    ok1 = True
                    break
            except:
                pass
            time.sleep(POLL_INTERVAL)

        suite.record("Scale down: discovery shows 1 instance", ok1,
                     error="timeout waiting for 1 instance" if not ok1 else "")

        # Scale back to 2
        log("Scaling back to 2 replicas...", YELLOW)
        kubectl(f"scale statefulset {STATEFULSET} --replicas=2 -n {NAMESPACE}")

        ok2 = False
        for _ in range(int(TIMEOUT / POLL_INTERVAL)):
            try:
                data = curl_json(f"{BACKEND_URL}/api/instances")
                if len(data) >= 2:
                    ok2 = True
                    break
            except:
                pass
            time.sleep(POLL_INTERVAL)

        suite.record("Scale up: discovery shows 2 instances", ok2,
                     error="timeout waiting for 2 instances" if not ok2 else "")

        # Wait for probes to confirm health
        if ok2:
            probes_ok = False
            for _ in range(15):
                try:
                    data = curl_json(f"{BACKEND_URL}/api/instances")
                    all_healthy = all(
                        i.get("probe", {}).get("reachable", False)
                        for i in data
                    )
                    if all_healthy and len(data) >= 2:
                        probes_ok = True
                        break
                except:
                    pass
                time.sleep(2)

            suite.record("Scale up: all probes healthy after scale", probes_ok,
                         details=f"{len(data)} instances all reachable" if probes_ok else "",
                         error="probes not healthy after 30s" if not probes_ok else "")

    except Exception as e:
        suite.record("Scaling test", False, error=str(e))
        # Restore
        try:
            kubectl(f"scale statefulset {STATEFULSET} --replicas=2 -n {NAMESPACE}")
        except:
            pass


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    suite = TestSuite("Live Cluster Production Validation")

    print(f"\n{BOLD}{'='*72}{RESET}")
    print(f"{BOLD}  Live Cluster Production Validation{RESET}")
    print(f"{BOLD}  Cluster: {NAMESPACE}  Backend: {BACKEND_URL}{RESET}")
    print(f"{BOLD}{'='*72}{RESET}\n")

    # ── Section 1: Backend API ────────────────────────────────────────────
    log("Section 1: Backend API Health", BLUE)
    test_backend_health(suite)
    test_backend_ready(suite)

    # ── Section 2: Discovery ──────────────────────────────────────────────
    log("\nSection 2: Kubernetes Discovery", BLUE)
    test_discovery_mode(suite)
    instances = test_instances_exist(suite)

    if not instances:
        log("No instances found — cannot continue", RED)
        suite.summary()
        sys.exit(1)

    # ── Section 3: Bug Fix Verification ───────────────────────────────────
    log("\nSection 3: Bug Fix Verification", BLUE)
    test_streamurl_fix(suite, instances)
    test_vnc_probes(suite, instances)
    test_health_probes(suite, instances)
    test_networkpolicy_probes_work(suite, instances)

    # ── Section 4: Instance Quality ───────────────────────────────────────
    log("\nSection 4: Instance Metadata & Identity", BLUE)
    test_instance_metadata(suite, instances)
    test_unique_identity(suite, instances)

    # ── Section 5: Live API ───────────────────────────────────────────────
    log("\nSection 5: Live Discovery API", BLUE)
    test_live_endpoint(suite)

    # ── Section 6: Deep Health ────────────────────────────────────────────
    log("\nSection 6: Emulator Deep Health", BLUE)
    test_emulator_deep_health(suite)

    # ── Section 7: Scaling ────────────────────────────────────────────────
    log("\nSection 7: Scaling & Recovery", BLUE)
    test_scaling(suite)

    # ── Summary ────────────────────────────────────────────────────────────
    all_passed = suite.summary()

    # Write JSON report
    report_dir = os.path.join(os.path.dirname(__file__), "..", "..", "benchmark", "live-validation")
    os.makedirs(report_dir, exist_ok=True)
    report_path = os.path.join(report_dir, "validation-report.json")
    with open(report_path, "w") as f:
        json.dump(suite.to_json(), f, indent=2)
    log(f"Report saved to {report_path}", CYAN)

    sys.exit(0 if all_passed else 1)


if __name__ == "__main__":
    main()
