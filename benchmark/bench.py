#!/usr/bin/env python3
"""
Lego Loco Cluster — Real Benchmark Harness
===========================================

Replaces the original stub with actual metric collection via:
  - Emulator health endpoint probing (FPS, CPU, memory, status)
  - Docker stats for container-level resource usage
  - Kubernetes pod discovery and scaling
  - End-to-end latency probing

Generates CSV + Markdown performance report.

Usage:
  python bench.py --mode k8s --replicas 1 3 9
  python bench.py --mode docker
  python bench.py --mode direct --instances localhost:8080
"""

import argparse
import csv
import json
import os
import re
import subprocess
import sys
import time
from collections import OrderedDict
from datetime import datetime
from pathlib import Path
from statistics import mean


# ---------------------------------------------------------------------------
# Metric collection helpers
# ---------------------------------------------------------------------------

def docker_stats_snapshot(container_prefix="emulator"):
    """Collect CPU% and MemMB from running Docker containers."""
    try:
        raw = subprocess.check_output(
            ["docker", "stats", "--no-stream", "--format",
             "{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"],
            timeout=15, text=True,
        )
    except (subprocess.SubprocessError, FileNotFoundError):
        return []

    results = []
    for line in raw.strip().splitlines():
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        name, cpu_str, mem_str = parts[0], parts[1], parts[2]
        if container_prefix not in name.lower():
            continue
        cpu = float(cpu_str.replace("%", ""))
        mem_match = re.search(r"([\d.]+)\s*(MiB|GiB|KiB)", mem_str)
        mem_mb = 0.0
        if mem_match:
            val = float(mem_match.group(1))
            unit = mem_match.group(2)
            if unit == "GiB":
                mem_mb = val * 1024
            elif unit == "KiB":
                mem_mb = val / 1024
            else:
                mem_mb = val
        results.append({"name": name, "cpu_pct": cpu, "mem_mb": round(mem_mb, 1)})
    return results


def probe_health_endpoint(host, port=8080, path="/health", timeout=5):
    """Probe an emulator health endpoint and parse JSON metrics."""
    import urllib.request
    url = f"http://{host}:{port}{path}"
    try:
        t0 = time.monotonic()
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            latency_ms = round((time.monotonic() - t0) * 1000, 1)
            data = json.loads(resp.read().decode())
            return {
                "probe_latency_ms": latency_ms,
                "qemu_healthy": data.get("qemu_healthy", False),
                "display_active": data.get("video", {}).get("display_active", False),
                "estimated_fps": data.get("video", {}).get("estimated_frame_rate", 0),
                "cpu_usage": data.get("performance", {}).get("cpu_usage", 0),
                "mem_usage_mb": data.get("performance", {}).get("memory_usage", 0),
                "network_bridge_up": data.get("network", {}).get("bridge_up", False),
                "network_tap_up": data.get("network", {}).get("tap_up", False),
                "overall_status": data.get("overall_status", "unknown"),
            }
    except Exception as e:
        return {"error": str(e), "probe_latency_ms": -1}


def kubectl_get_emulator_pods(namespace="loco"):
    """List emulator pod IPs from Kubernetes."""
    try:
        raw = subprocess.check_output(
            ["kubectl", "get", "pods", "-n", namespace,
             "-l", "app.kubernetes.io/component=emulator",
             "-o", "jsonpath={range .items[*]}{.metadata.name},{.status.podIP}\\n{end}"],
            timeout=15, text=True,
        )
    except (subprocess.SubprocessError, FileNotFoundError):
        return []
    pods = []
    for line in raw.strip().splitlines():
        parts = line.split(",")
        if len(parts) == 2 and parts[1]:
            pods.append({"name": parts[0], "ip": parts[1]})
    return pods


# ---------------------------------------------------------------------------
# Benchmark execution
# ---------------------------------------------------------------------------

def run_benchmark_pass(targets, duration_secs=60, sample_interval=5):
    """Sample health endpoints for `duration_secs`. Returns aggregate metrics."""
    print(f"  Benchmarking {len(targets)} instances for {duration_secs}s ...")
    per_instance = {t["name"]: [] for t in targets}

    samples = int(duration_secs / sample_interval)
    for s in range(samples):
        for t in targets:
            health = probe_health_endpoint(t["ip"], t.get("health_port", 8080))
            health["sample"] = s
            health["timestamp"] = datetime.utcnow().isoformat()
            per_instance[t["name"]].append(health)
        time.sleep(sample_interval)

    docker_snapshot = docker_stats_snapshot()
    docker_by_name = {d["name"]: d for d in docker_snapshot}

    aggregated = []
    for t in targets:
        samples_list = per_instance[t["name"]]
        good = [s for s in samples_list if "error" not in s]
        if not good:
            aggregated.append({"instance": t["name"], "status": "unreachable", "samples": len(samples_list)})
            continue

        fps_vals = [s["estimated_fps"] for s in good if s.get("estimated_fps", 0) > 0]
        latency_vals = [s["probe_latency_ms"] for s in good if s.get("probe_latency_ms", 0) > 0]
        cpu_vals = [s["cpu_usage"] for s in good if s.get("cpu_usage")]
        mem_vals = [s["mem_usage_mb"] for s in good if s.get("mem_usage_mb", 0) > 0]
        docker_info = docker_by_name.get(t["name"], {})

        aggregated.append(OrderedDict([
            ("instance", t["name"]),
            ("status", good[-1].get("overall_status", "unknown")),
            ("samples", len(good)),
            ("avg_fps", round(mean(fps_vals), 1) if fps_vals else 0),
            ("min_fps", min(fps_vals) if fps_vals else 0),
            ("max_fps", max(fps_vals) if fps_vals else 0),
            ("avg_latency_ms", round(mean(latency_vals), 1) if latency_vals else -1),
            ("avg_cpu_pct", round(mean(cpu_vals), 1) if cpu_vals else 0),
            ("docker_cpu_pct", docker_info.get("cpu_pct", 0)),
            ("docker_mem_mb", docker_info.get("mem_mb", 0)),
            ("mem_usage_pct", round(mean(mem_vals), 1) if mem_vals else 0),
            ("qemu_healthy", all(s.get("qemu_healthy") for s in good)),
            ("display_active", all(s.get("display_active") for s in good)),
            ("network_ok", all(s.get("network_bridge_up") and s.get("network_tap_up") for s in good)),
        ]))

    return aggregated


def deploy_replicas(replicas, mode="k8s"):
    """Scale emulator instances."""
    if mode == "k8s":
        try:
            ns = os.environ.get("NAMESPACE", "loco")
            subprocess.run(["kubectl", "scale", "statefulset", "-n", ns,
                            "--all", f"--replicas={replicas}"], check=True, timeout=30)
            subprocess.run(["kubectl", "rollout", "status", "statefulset", "-n", ns,
                            "--timeout=300s"], check=False, timeout=310)
        except (subprocess.SubprocessError, FileNotFoundError) as e:
            print(f"  Scale failed: {e}")
    elif mode == "docker":
        try:
            env = os.environ.copy()
            env["REPLICAS"] = str(replicas)
            subprocess.run(["./scripts/deploy_single.sh"], check=True, env=env, timeout=120)
        except (subprocess.SubprocessError, FileNotFoundError) as e:
            print(f"  Deploy failed: {e}")


def discover_targets(mode="k8s", direct=None):
    """Discover emulator instances."""
    if direct:
        targets = []
        # Support both space-separated (nargs="+") and comma-separated instances
        expanded = []
        for item in direct:
            expanded.extend(item.split(","))
        for addr in expanded:
            addr = addr.strip()
            if not addr:
                continue
            host, _, port = addr.partition(":")
            targets.append({"name": f"direct-{host}", "ip": host,
                            "health_port": int(port) if port else 8080})
        return targets
    if mode == "k8s":
        return [{"name": p["name"], "ip": p["ip"], "health_port": 8080}
                for p in kubectl_get_emulator_pods()]
    else:
        # Docker Compose mode: detect whether we're inside the compose
        # network (containers reachable by name:8080) or on the host
        # (mapped to localhost:808X).
        import socket
        inside_network = False
        try:
            socket.getaddrinfo("loco-emulator-0", 8080, socket.AF_INET)
            inside_network = True
        except socket.gaierror:
            pass

        targets = []
        replicas = int(os.environ.get("REPLICAS", 9))
        for i in range(replicas):
            if inside_network:
                # Inside compose network — use container DNS names
                targets.append({
                    "name": f"loco-emulator-{i}",
                    "ip": f"loco-emulator-{i}",
                    "health_port": 8080,
                })
            else:
                # Running from host — use mapped ports
                targets.append({
                    "name": f"emulator-{i}",
                    "ip": "localhost",
                    "health_port": 8080 + i,
                })
        return targets


# ---------------------------------------------------------------------------
# Report generation
# ---------------------------------------------------------------------------

def write_csv(results, filepath):
    if not results:
        return
    with open(filepath, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(results[0].keys()))
        writer.writeheader()
        writer.writerows(results)
    print(f"  CSV written: {filepath}")


def write_markdown_report(all_runs, filepath, thresholds=None):
    t = thresholds or {"min_fps": 15, "max_latency": 250, "max_cpu": 80}
    lines = [
        "# Lego Loco Cluster — Performance Benchmark Report",
        "", f"**Generated**: {datetime.utcnow().isoformat()}Z", "",
    ]
    for run_info in all_runs:
        replicas = run_info["replicas"]
        data = run_info["data"]
        lines.append(f"## {replicas} Replica(s)")
        lines.append("")
        if not data:
            lines.append("_No data collected._")
            lines.append("")
            continue
        lines.append("| Instance | Status | Avg FPS | Latency ms | CPU % | Mem % | QEMU | Display | Net |")
        lines.append("|----------|--------|---------|------------|-------|-------|------|---------|-----|")
        for row in data:
            mem_val = row.get('docker_mem_mb', 0) or row.get('mem_usage_pct', 0)
            mem_label = f"{mem_val} MB" if row.get('docker_mem_mb', 0) else f"{mem_val}%"
            lines.append(
                f"| {row.get('instance','-')} | {row.get('status','-')} | {row.get('avg_fps',0)} "
                f"| {row.get('avg_latency_ms',-1)} | {row.get('avg_cpu_pct',0)} "
                f"| {mem_label} "
                f"| {'✅' if row.get('qemu_healthy') else '❌'} "
                f"| {'✅' if row.get('display_active') else '❌'} "
                f"| {'✅' if row.get('network_ok') else '❌'} |")
        lines.append("")

    lines.append("## Pass / Fail Criteria")
    lines.append("| Metric | Threshold | Status |")
    lines.append("|--------|-----------|--------|")
    if all_runs and all_runs[-1]["data"]:
        last = all_runs[-1]["data"]
        fps_all = [r["avg_fps"] for r in last if r.get("avg_fps", 0) > 0]
        lat_all = [r["avg_latency_ms"] for r in last if r.get("avg_latency_ms", -1) > 0]
        cpu_all = [r["avg_cpu_pct"] for r in last if r.get("avg_cpu_pct", 0) > 0]
        lines.append(f"| Min FPS >= {t['min_fps']} | {t['min_fps']} | {'✅' if (fps_all and min(fps_all)>=t['min_fps']) else '❌'} |")
        lines.append(f"| Max Latency <= {t['max_latency']}ms | {t['max_latency']} | {'✅' if (lat_all and max(lat_all)<=t['max_latency']) else '❌'} |")
        lines.append(f"| Max CPU <= {t['max_cpu']}% | {t['max_cpu']} | {'✅' if (cpu_all and max(cpu_all)<=t['max_cpu']) else '❌'} |")
    lines.append("")

    Path(filepath).write_text("\n".join(lines))
    print(f"  Report written: {filepath}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Lego Loco Cluster Benchmark Harness")
    parser.add_argument("--replicas", nargs="+", type=int, default=[1, 3, 9])
    parser.add_argument("--mode", choices=["k8s", "docker", "direct"], default="k8s")
    parser.add_argument("--instances", nargs="+", help="Direct host:port targets")
    parser.add_argument("--duration", type=int, default=60)
    parser.add_argument("--interval", type=int, default=5)
    parser.add_argument("--output-dir", default="benchmark")
    parser.add_argument("--skip-scale", action="store_true")
    parser.add_argument("--csv", default="results.csv")
    parser.add_argument("--max-latency", type=int, default=250,
                        help="Max acceptable latency in ms (default 250)")
    parser.add_argument("--min-fps", type=int, default=15,
                        help="Min acceptable FPS (default 15)")
    parser.add_argument("--max-cpu", type=int, default=80,
                        help="Max acceptable CPU percent (default 80)")
    args = parser.parse_args()

    os.makedirs(args.output_dir, exist_ok=True)
    all_runs = []
    all_rows = []

    for replicas in args.replicas:
        print(f"\n{'='*60}\nBenchmark: {replicas} replica(s)\n{'='*60}")
        if not args.skip_scale and args.mode != "direct":
            deploy_replicas(replicas, mode=args.mode)
            print("  Waiting 30s for stabilisation ...")
            time.sleep(30)

        targets = discover_targets(mode=args.mode, direct=args.instances)
        if not targets:
            print("  WARNING: No targets discovered!")
            all_runs.append({"replicas": replicas, "data": []})
            continue

        data = run_benchmark_pass(targets, duration_secs=args.duration,
                                  sample_interval=args.interval)
        for row in data:
            row["replicas"] = replicas
        all_rows.extend(data)
        all_runs.append({"replicas": replicas, "data": data})

        for row in data:
            print(f"  {row.get('instance','?'):30s}  status={row.get('status','?')}  fps={row.get('avg_fps',0)}")

    write_csv(all_rows, os.path.join(args.output_dir, args.csv))
    thresholds = {"min_fps": args.min_fps, "max_latency": args.max_latency,
                  "max_cpu": args.max_cpu}
    write_markdown_report(all_runs, os.path.join(args.output_dir, "BENCHMARK_REPORT.md"),
                          thresholds=thresholds)

    # CI gate exit code
    if all_runs and all_runs[-1]["data"]:
        last = all_runs[-1]["data"]
        fps_all = [r["avg_fps"] for r in last if r.get("avg_fps", 0) > 0]
        lat_all = [r["avg_latency_ms"] for r in last if r.get("avg_latency_ms", -1) > 0]
        fail = False
        if fps_all and min(fps_all) < args.min_fps:
            print(f"\n❌ BENCHMARK FAILED: FPS {min(fps_all)} below {args.min_fps}")
            fail = True
        if lat_all and max(lat_all) > args.max_latency:
            print(f"\n❌ BENCHMARK FAILED: Latency {max(lat_all):.0f}ms exceeds {args.max_latency}ms")
            fail = True
        if fail:
            sys.exit(1)
    print("\n✅ Benchmark complete")


if __name__ == "__main__":
    main()
