#!/usr/bin/env python3
"""
Lego Loco LAN Session Automation
=================================
Uses the QMP agent REST API to control all QEMU instances,
navigate Lego Loco menus, and set up a multiplayer LAN session.

This script:
1. Waits for all instances to be healthy
2. Uses QMP input injection to navigate menus on each instance
3. Instance 0 creates a LAN game (host)
4. Instances 1-N join the LAN game
5. Verifies all instances are connected
6. Runs the game for a specified duration while benchmark monitor collects metrics

Usage:
  python3 lan_session_automation.py --instances 9 --backend http://backend:3001 --duration 120
  
  # Or from within the cluster:
  python3 lan_session_automation.py --qmp-hosts "emulator-0:9090,emulator-1:9090,..."
"""

import argparse
import json
import sys
import time
import urllib.request
import urllib.error
from datetime import datetime


class QMPClient:
    """HTTP client for the QMP agent REST API."""

    def __init__(self, host, port=9090):
        self.base_url = f"http://{host}:{port}"

    def health(self):
        return self._get("/health")

    def status(self, instance_id):
        return self._get(f"/status/{instance_id}")

    def send_key(self, instance_id, key, action="tap"):
        return self._post(f"/input/{instance_id}", {
            "type": "key", "key": key, "action": action
        })

    def send_mouse(self, instance_id, x, y, button="left", action="click"):
        return self._post(f"/input/{instance_id}", {
            "type": "mouse", "x": x, "y": y, "button": button, "action": action
        })

    def send_keys(self, instance_id, keys, delay=0.15):
        """Send a sequence of key taps with delay between each."""
        results = []
        for key in keys:
            r = self.send_key(instance_id, key, "tap")
            results.append(r)
            time.sleep(delay)
        return results

    def type_text(self, instance_id, text, delay=0.1):
        """Type a text string character by character."""
        for char in text:
            key = char.lower() if char.isalpha() else char
            self.send_key(instance_id, key, "tap")
            time.sleep(delay)

    def _get(self, path):
        try:
            req = urllib.request.Request(f"{self.base_url}{path}")
            with urllib.request.urlopen(req, timeout=5) as resp:
                return json.loads(resp.read().decode())
        except Exception as e:
            return {"error": str(e)}

    def _post(self, path, data):
        try:
            body = json.dumps(data).encode()
            req = urllib.request.Request(
                f"{self.base_url}{path}",
                data=body,
                headers={"Content-Type": "application/json"},
                method="POST"
            )
            with urllib.request.urlopen(req, timeout=5) as resp:
                return json.loads(resp.read().decode())
        except Exception as e:
            return {"error": str(e)}


class BackendClient:
    """Client for the Lego Loco backend API."""

    def __init__(self, url):
        self.base_url = url.rstrip("/")

    def get_instances(self):
        return self._get("/api/instances")

    def get_benchmark(self):
        return self._get("/api/benchmark/live")

    def get_lan_status(self):
        return self._get("/api/lan-status")

    def _get(self, path):
        try:
            req = urllib.request.Request(f"{self.base_url}{path}")
            with urllib.request.urlopen(req, timeout=10) as resp:
                return json.loads(resp.read().decode())
        except Exception as e:
            return {"error": str(e)}


def wait_for_instances(backend, expected_count, timeout=300):
    """Wait for all instances to be healthy."""
    print(f"  Waiting for {expected_count} healthy instances (timeout {timeout}s)...")
    start = time.time()
    while time.time() - start < timeout:
        bench = backend.get_benchmark()
        if "error" not in bench:
            summary = bench.get("summary", {})
            healthy = summary.get("healthyCount", 0)
            total = summary.get("totalCount", 0)
            print(f"    {healthy}/{total} healthy (need {expected_count})")
            if healthy >= expected_count:
                return True
        time.sleep(10)
    return False


def lego_loco_navigate_to_multiplayer(qmp, instance_id):
    """Navigate Lego Loco main menu to multiplayer/LAN option.
    
    Lego Loco main menu navigation (approximate):
    - After game loads: main menu with Play, Options, etc.
    - Need to click on the multiplayer/network play button
    - Then select LAN game
    
    Note: Exact coordinates depend on the game resolution (1024x768).
    These are approximate and may need tuning based on actual game state.
    """
    print(f"  Instance {instance_id}: Navigating to multiplayer...")

    # First, dismiss any startup dialogs by pressing Enter/Escape
    qmp.send_key(instance_id, "esc")
    time.sleep(1)
    qmp.send_key(instance_id, "enter")
    time.sleep(2)

    # Click on the game window to ensure focus
    qmp.send_mouse(instance_id, 512, 384, "left", "click")
    time.sleep(1)

    return True


def host_create_game(qmp, instance_id):
    """Instance 0: Create a LAN game as host.
    
    In Lego Loco, the host creates a new game world and others can join.
    The multiplayer setup uses DirectPlay over the LAN.
    """
    print(f"  Instance {instance_id}: Creating LAN game (host)...")

    # Navigate to multiplayer menu
    lego_loco_navigate_to_multiplayer(qmp, instance_id)
    time.sleep(2)

    # Click "Host Game" / "Create Game" button (approximate position)
    # Lego Loco multiplayer dialog is centered on screen
    qmp.send_mouse(instance_id, 512, 350, "left", "click")
    time.sleep(3)

    # Confirm game creation
    qmp.send_key(instance_id, "enter")
    time.sleep(5)  # Wait for game to start hosting

    print(f"  Instance {instance_id}: Game hosted, waiting for players...")
    return True


def client_join_game(qmp, instance_id):
    """Instance N: Join an existing LAN game.
    
    The client looks for available LAN games via DirectPlay broadcast
    and joins the first one found.
    """
    print(f"  Instance {instance_id}: Joining LAN game...")

    # Navigate to multiplayer menu
    lego_loco_navigate_to_multiplayer(qmp, instance_id)
    time.sleep(3)

    # Click "Join Game" / "Find Games" button
    qmp.send_mouse(instance_id, 512, 420, "left", "click")
    time.sleep(5)  # Wait for game discovery

    # Select the first found game and join
    qmp.send_mouse(instance_id, 512, 300, "left", "click")
    time.sleep(1)
    qmp.send_key(instance_id, "enter")
    time.sleep(5)  # Wait for connection

    print(f"  Instance {instance_id}: Join attempt complete")
    return True


def run_game_session(qmp, instance_ids, duration=60):
    """Run the game for a specified duration, periodically injecting activity.
    
    During the session:
    - Move the camera around on each instance
    - Click on various game elements
    - This generates activity for the benchmark to measure
    """
    print(f"\n  Running game session for {duration}s across {len(instance_ids)} instances...")
    start = time.time()
    cycle = 0

    while time.time() - start < duration:
        cycle += 1
        elapsed = int(time.time() - start)
        print(f"    Cycle {cycle} ({elapsed}s/{duration}s)")

        for iid in instance_ids:
            # Move mouse around to generate display activity
            positions = [(300, 300), (500, 400), (700, 300), (500, 500)]
            pos = positions[cycle % len(positions)]
            qmp.send_mouse(iid, pos[0], pos[1], None, "move")
            time.sleep(0.1)

            # Occasionally click
            if cycle % 5 == 0:
                qmp.send_mouse(iid, pos[0], pos[1], "left", "click")

            # Occasionally press arrow keys (camera movement)
            if cycle % 3 == 0:
                arrows = ["up", "down", "left", "right"]
                qmp.send_key(iid, arrows[cycle % 4], "tap")

        time.sleep(5)

    print(f"  Game session complete ({duration}s)")


def main():
    parser = argparse.ArgumentParser(description="Lego Loco LAN Session Automation")
    parser.add_argument("--instances", type=int, default=9,
                        help="Number of instances to orchestrate")
    parser.add_argument("--backend", default="http://localhost:3001",
                        help="Backend API URL")
    parser.add_argument("--qmp-port", type=int, default=9090,
                        help="QMP agent port on each emulator")
    parser.add_argument("--qmp-hosts", default="",
                        help="Comma-separated QMP agent host:port pairs")
    parser.add_argument("--duration", type=int, default=120,
                        help="Game session duration in seconds")
    parser.add_argument("--skip-wait", action="store_true",
                        help="Skip waiting for instances to become healthy")
    parser.add_argument("--skip-navigate", action="store_true",
                        help="Skip game menu navigation (just inject activity)")
    parser.add_argument("--dry-run", action="store_true",
                        help="Print actions without executing")
    args = parser.parse_args()

    print(f"\n{'='*60}")
    print(f"  Lego Loco LAN Session Automation")
    print(f"  {datetime.utcnow().isoformat()}Z")
    print(f"  Instances: {args.instances}  Duration: {args.duration}s")
    print(f"{'='*60}\n")

    backend = BackendClient(args.backend)

    # Step 1: Wait for all instances
    if not args.skip_wait:
        print("Step 1: Waiting for instances...")
        if not wait_for_instances(backend, args.instances, timeout=600):
            print("ERROR: Not all instances became healthy")
            # Continue anyway for partial testing
            bench = backend.get_benchmark()
            healthy = bench.get("summary", {}).get("healthyCount", 0)
            print(f"  Proceeding with {healthy} healthy instances")

    # Step 2: Set up QMP connections
    print("\nStep 2: Setting up QMP connections...")
    qmp_clients = {}

    if args.qmp_hosts:
        # Direct QMP host specification
        for pair in args.qmp_hosts.split(","):
            parts = pair.strip().split(":")
            host = parts[0]
            port = int(parts[1]) if len(parts) > 1 else args.qmp_port
            # Determine instance ID from hostname
            for i in range(args.instances):
                if f"-{i}" in host or host.endswith(str(i)):
                    qmp_clients[str(i)] = QMPClient(host, port)
                    break
    else:
        # Discover from backend
        instances = backend.get_instances()
        if isinstance(instances, list):
            for inst in instances[:args.instances]:
                iid = str(inst.get("instanceId", inst.get("id", "")))
                host = inst.get("host", inst.get("podIP", "localhost"))
                qmp_clients[iid] = QMPClient(host, args.qmp_port)
                print(f"  Instance {iid}: QMP at {host}:{args.qmp_port}")

    if not qmp_clients:
        print("WARNING: No QMP clients configured. Using activity injection only.")

    instance_ids = sorted(qmp_clients.keys())
    print(f"  Total QMP clients: {len(instance_ids)}")

    # Step 3: Navigate to multiplayer
    if not args.skip_navigate and qmp_clients:
        print("\nStep 3: Setting up LAN game...")

        if args.dry_run:
            print("  [DRY RUN] Would create game on instance 0, join on others")
        else:
            # Host creates game
            if "0" in qmp_clients:
                host_create_game(qmp_clients["0"], "0")
                time.sleep(5)

            # Others join
            for iid in instance_ids:
                if iid != "0":
                    client_join_game(qmp_clients[iid], iid)
                    time.sleep(3)
    else:
        print("\nStep 3: Skipping navigation (--skip-navigate)")

    # Step 4: Run game session with activity injection
    print(f"\nStep 4: Running game session ({args.duration}s)...")

    if args.dry_run:
        print(f"  [DRY RUN] Would inject activity for {args.duration}s")
    elif qmp_clients:
        run_game_session(
            # Use the first QMP client as a "router" to all instances
            qmp_clients[instance_ids[0]] if len(instance_ids) == 1 else type('MultiQMP', (), {
                'send_mouse': lambda self, iid, *a, **kw: qmp_clients.get(iid, qmp_clients[instance_ids[0]]).send_mouse(iid, *a, **kw),
                'send_key': lambda self, iid, *a, **kw: qmp_clients.get(iid, qmp_clients[instance_ids[0]]).send_key(iid, *a, **kw),
            })(),
            instance_ids,
            duration=args.duration
        )

    # Step 5: Final benchmark snapshot
    print("\nStep 5: Final benchmark snapshot...")
    bench = backend.get_benchmark()
    if "error" not in bench:
        summary = bench.get("summary", {})
        print(f"  Instances: {summary.get('totalCount', 0)}")
        print(f"  Healthy:   {summary.get('healthyCount', 0)}")
        print(f"  Avg FPS:   {summary.get('avgFps', 0)}")
        print(f"  Avg Lat:   {summary.get('avgLatency', 0)}ms")
        print(f"  Avg CPU:   {summary.get('avgCpu', 0)}%")
        print(f"  Network:   {summary.get('networkMode', 'unknown')}")
    else:
        print(f"  Error fetching benchmark: {bench.get('error')}")

    lan = backend.get_lan_status()
    if "error" not in lan:
        print(f"  LAN Healthy: {lan.get('overallHealthy', False)}")
        print(f"  Connectivity pairs: {len(lan.get('connectivity', []))}")

    print(f"\n{'='*60}")
    print(f"  Session complete!")
    print(f"{'='*60}\n")


if __name__ == "__main__":
    main()
