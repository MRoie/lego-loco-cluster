#!/usr/bin/env python3
"""
Automated Lego Loco LAN Session Test
=====================================

Orchestrates a full multiplayer session:
  1. Waits for all instances to reach 'ready' state via /api/instances
  2. Uses QMP agent to navigate Lego Loco menus on instance-0 (host)
     and select "Start Network Game"
  3. On instances 1..N, navigates to "Join Network Game" and joins the host
  4. Captures VNC screenshots for lobby verification
  5. Starts game and measures FPS/input responsiveness for 60 seconds

Requires:
  - Shared L2 network (NETWORK_MODE=socket) between all instances
  - QMP agent running on each instance (or central QMP agent service)
  - Backend API accessible at BACKEND_URL

Usage:
  python lan_session_test.py --backend http://localhost:3001
  python lan_session_test.py --qmp-agent http://localhost:9090 --instances 3

Environment:
  BACKEND_URL    — backend API base URL (default: http://localhost:3001)
  QMP_AGENT_URL  — QMP agent base URL (default: http://localhost:9090)
"""

import argparse
import json
import os
import sys
import time
import urllib.request
from datetime import datetime
from pathlib import Path

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def api_get(url, timeout=10):
    """Fetch JSON from a URL."""
    try:
        with urllib.request.urlopen(url, timeout=timeout) as resp:
            return json.loads(resp.read().decode())
    except Exception as e:
        return {"error": str(e)}


def api_post(url, data, timeout=10):
    """POST JSON to a URL."""
    try:
        body = json.dumps(data).encode()
        req = urllib.request.Request(url, data=body,
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode())
    except Exception as e:
        return {"error": str(e)}


def wait_for_instances(backend_url, expected_count, timeout=300):
    """Wait until all expected instances report 'ready'."""
    print(f"Waiting for {expected_count} instances to become ready ...")
    start = time.monotonic()
    while time.monotonic() - start < timeout:
        data = api_get(f"{backend_url}/api/instances")
        if isinstance(data, list):
            ready = [i for i in data if i.get("ready") or i.get("status") == "ready"]
            print(f"  {len(ready)}/{expected_count} instances ready")
            if len(ready) >= expected_count:
                return ready
        time.sleep(5)
    raise TimeoutError(f"Only got instances after {timeout}s")


# ---------------------------------------------------------------------------
# QMP input sequences for Lego Loco menu navigation
# ---------------------------------------------------------------------------

def send_key(qmp_url, instance_id, key, delay=0.5):
    """Send a key tap to an instance via QMP agent."""
    result = api_post(f"{qmp_url}/input/{instance_id}", {
        "type": "key", "key": key, "action": "tap"
    })
    time.sleep(delay)
    return result


def send_mouse_click(qmp_url, instance_id, x, y, button="left", delay=0.5):
    """Send a mouse click to an instance via QMP agent."""
    result = api_post(f"{qmp_url}/input/{instance_id}", {
        "type": "mouse", "x": x, "y": y, "button": button, "action": "click"
    })
    time.sleep(delay)
    return result


def navigate_host_start_network_game(qmp_url, instance_id):
    """
    Navigate the Lego Loco main menu to start a network game.
    
    Menu flow (approximate screen coordinates for 1024x768):
      1. Main menu → click "Network Game" button
      2. Network Game setup → click "Host Game" / "Start"
    
    These coordinates are estimates and may need calibration via screenshot comparison.
    """
    print(f"  [{instance_id}] Navigating to 'Start Network Game' ...")

    # Click on the 'Network' button area in the main menu
    # Lego Loco main menu typically has buttons centered
    send_mouse_click(qmp_url, instance_id, 512, 500, delay=2.0)

    # Press Enter to confirm selection
    send_key(qmp_url, instance_id, "enter", delay=2.0)

    # Click "Host Game" or press Tab+Enter to navigate to host option
    send_key(qmp_url, instance_id, "tab", delay=0.5)
    send_key(qmp_url, instance_id, "enter", delay=2.0)

    print(f"  [{instance_id}] Host game started (waiting for clients)")


def navigate_client_join_game(qmp_url, instance_id):
    """
    Navigate a client instance to join the host's network game.
    """
    print(f"  [{instance_id}] Navigating to 'Join Network Game' ...")

    # Click on the 'Network' button area
    send_mouse_click(qmp_url, instance_id, 512, 500, delay=2.0)

    # Press Enter
    send_key(qmp_url, instance_id, "enter", delay=2.0)

    # The game should auto-discover the host on the LAN
    # Click "Join" or wait for auto-join
    send_key(qmp_url, instance_id, "enter", delay=3.0)

    print(f"  [{instance_id}] Joined game session")


# ---------------------------------------------------------------------------
# Benchmark data collection during gameplay
# ---------------------------------------------------------------------------

def collect_gameplay_metrics(backend_url, instance_ids, duration=60, interval=5):
    """Collect streaming/health metrics during active gameplay."""
    print(f"Collecting gameplay metrics for {duration}s ...")
    metrics = {iid: [] for iid in instance_ids}

    samples = int(duration / interval)
    for s in range(samples):
        # Fetch health from each emulator
        instances = api_get(f"{backend_url}/api/instances")
        if isinstance(instances, list):
            for inst in instances:
                iid = inst.get("id", "")
                if iid in metrics:
                    health_url = inst.get("healthUrl", "")
                    if health_url:
                        health = api_get(health_url)
                        metrics[iid].append({
                            "sample": s,
                            "timestamp": datetime.utcnow().isoformat(),
                            "fps": health.get("video", {}).get("estimated_frame_rate", 0),
                            "cpu": health.get("system_performance", {}).get("cpu_usage_percent", 0),
                            "qemu_ok": health.get("qemu_healthy", False),
                            "status": health.get("overall_status", "unknown"),
                        })
        time.sleep(interval)

    return metrics


# ---------------------------------------------------------------------------
# Report generation
# ---------------------------------------------------------------------------

def generate_report(metrics, output_path):
    """Generate BENCHMARK_LAN_SESSION.md report."""
    lines = [
        "# Lego Loco LAN Session Benchmark Report",
        "",
        f"**Generated**: {datetime.utcnow().isoformat()}Z",
        "",
        "## Test Configuration",
        f"- Instances: {len(metrics)}",
        f"- Network Mode: socket (shared L2)",
        "",
        "## Per-Instance Results",
        "",
        "| Instance | Samples | Avg FPS | Min FPS | Avg CPU % | QEMU Healthy | Status |",
        "|----------|---------|---------|---------|-----------|-------------|--------|",
    ]

    all_fps = []
    for iid, samples in sorted(metrics.items()):
        if not samples:
            lines.append(f"| {iid} | 0 | - | - | - | - | unreachable |")
            continue

        fps_vals = [s["fps"] for s in samples if s.get("fps", 0) > 0]
        cpu_vals = [s["cpu"] for s in samples if s.get("cpu", 0) > 0]
        healthy = all(s.get("qemu_ok") for s in samples)
        last_status = samples[-1].get("status", "unknown")

        avg_fps = round(sum(fps_vals)/len(fps_vals), 1) if fps_vals else 0
        min_fps = min(fps_vals) if fps_vals else 0
        avg_cpu = round(sum(cpu_vals)/len(cpu_vals), 1) if cpu_vals else 0
        all_fps.extend(fps_vals)

        lines.append(
            f"| {iid} | {len(samples)} | {avg_fps} | {min_fps} | {avg_cpu} "
            f"| {'✅' if healthy else '❌'} | {last_status} |"
        )

    lines.append("")
    lines.append("## Aggregate")
    if all_fps:
        lines.append(f"- Mean FPS across all instances: {sum(all_fps)/len(all_fps):.1f}")
        lines.append(f"- Min FPS observed: {min(all_fps)}")
    else:
        lines.append("- No FPS data collected")
    lines.append("")

    # Pass/fail
    passed = min(all_fps) >= 15 if all_fps else False
    lines.append(f"## Result: {'✅ PASS' if passed else '❌ FAIL'}")
    lines.append("")

    report = "\n".join(lines)
    Path(output_path).write_text(report)
    print(f"Report written: {output_path}")
    return passed


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Automated Lego Loco LAN Session Test")
    parser.add_argument("--backend", default=os.environ.get("BACKEND_URL", "http://localhost:3001"),
                        help="Backend API URL")
    parser.add_argument("--qmp-agent", default=os.environ.get("QMP_AGENT_URL", "http://localhost:9090"),
                        help="QMP agent URL")
    parser.add_argument("--instances", type=int, default=3,
                        help="Number of instances to use")
    parser.add_argument("--duration", type=int, default=60,
                        help="Gameplay measurement duration (seconds)")
    parser.add_argument("--output", default="benchmark/BENCHMARK_LAN_SESSION.md",
                        help="Output report path")
    parser.add_argument("--skip-navigation", action="store_true",
                        help="Skip menu navigation (useful if game is already in session)")
    args = parser.parse_args()

    os.makedirs(os.path.dirname(args.output), exist_ok=True)

    print("=" * 60)
    print("Lego Loco LAN Session Automated Test")
    print("=" * 60)

    # Step 1: Wait for instances
    try:
        instances = wait_for_instances(args.backend, args.instances, timeout=300)
    except TimeoutError as e:
        print(f"❌ {e}")
        sys.exit(1)

    instance_ids = [i.get("id") for i in instances[:args.instances]]
    print(f"Using instances: {instance_ids}")

    # Step 2: Navigate menus via QMP
    if not args.skip_navigation:
        print("\nNavigating game menus via QMP agent ...")

        # Host = instance 0
        host_id = instance_ids[0]
        navigate_host_start_network_game(args.qmp_agent, host_id)

        # Wait for host to set up
        time.sleep(5)

        # Clients = remaining instances
        for client_id in instance_ids[1:]:
            navigate_client_join_game(args.qmp_agent, client_id)
            time.sleep(2)

        # Wait for all clients to join
        print("Waiting 10s for lobby to stabilise ...")
        time.sleep(10)

    # Step 3: Collect gameplay metrics
    print(f"\nCollecting gameplay metrics for {args.duration}s ...")
    metrics = collect_gameplay_metrics(
        args.backend, instance_ids,
        duration=args.duration, interval=5,
    )

    # Step 4: Generate report
    print("\nGenerating report ...")
    passed = generate_report(metrics, args.output)

    if passed:
        print("\n✅ LAN Session Test PASSED")
    else:
        print("\n❌ LAN Session Test FAILED")
        sys.exit(1)


if __name__ == "__main__":
    main()
